package main

import (
	"context"
	"crypto/sha256"
	"encoding/json"
	"fmt"
	"github.com/ghodss/yaml"
	"github.com/golang/glog"
	"io/ioutil"
	"k8s.io/api/admission/v1beta1"
	corev1 "k8s.io/api/core/v1"
	metav1 "k8s.io/apimachinery/pkg/apis/meta/v1"
	"k8s.io/apimachinery/pkg/runtime"
	"k8s.io/apimachinery/pkg/runtime/serializer"
	"k8s.io/client-go/kubernetes"
	"k8s.io/client-go/rest"
	"log"
	"net/http"
	"os"
	"strconv"
	"strings"
	"sync"
	"time"
)

var (
	runtimeScheme = runtime.NewScheme()
	codecs        = serializer.NewCodecFactory(runtimeScheme)
	deserializer  = codecs.UniversalDeserializer()

	// (https://github.com/kubernetes/kubernetes/issues/57982)
	defaulter = runtime.ObjectDefaulter(runtimeScheme)
)

var (
	config, err1    = rest.InClusterConfig()
	clientset, err2 = kubernetes.NewForConfig(config)
	api             = clientset.CoreV1()
)

var ignoredNamespaces = []string{
	metav1.NamespaceSystem,
	metav1.NamespacePublic,
	"default",
}

const (
	admissionWebhookAnnotationInjectKey = "sidecar-injector-webhook.morven.me/inject"
	admissionWebhookAnnotationStatusKey = "sidecar-injector-webhook.morven.me/status"
)

type WebhookServer struct {
	sync.Mutex
	server *http.Server
}

// Webhook Server parameters
type WhSvrParameters struct {
	port           int    // webhook server port
	certFile       string // path to the x509 certificate for https
	keyFile        string // path to the x509 private key matching `CertFile`
	sidecarCfgFile string // path to sidecar injector configuration file
}

type Config struct {
	Containers []corev1.Container `yaml:"containers"`
	Volumes    []corev1.Volume    `yaml:"volumes"`
}

type patchOperation struct {
	Op    string      `json:"op"`
	Path  string      `json:"path"`
	Value interface{} `json:"value,omitempty"`
}

type NodeLabelStrategy struct {
	NodeLabel string
	Replicas  int
	Weight    int
}

var (
	serviceInstance = 1
)

func loadConfig(configFile string) (*Config, error) {
	data, err := ioutil.ReadFile(configFile)
	if err != nil {
		return nil, err
	}
	glog.Infof("New configuration: sha256sum %x", sha256.Sum256(data))

	var cfg Config
	if err := yaml.Unmarshal(data, &cfg); err != nil {
		return nil, err
	}

	return &cfg, nil
}

// Check whether the target resoured need to be mutated
func mutationRequired(ignoredList []string, metadata *metav1.ObjectMeta) bool {
	// skip special kubernete system namespaces
	for _, namespace := range BlockedNameSpaceList {
		if metadata.Namespace == namespace {
			glog.Infof("Skip mutation for %v for it's in special namespace:%v", metadata.Name, metadata.Namespace)
			return false
		}
	}
	return true
}

func updateNodeSelectors(target map[string]string, added map[string]string, basePath string) (patch []patchOperation) {
	for key, value := range added {
		if target == nil || target[key] == "" {
			target = map[string]string{}
			patch = append(patch, patchOperation{
				Op:   "add",
				Path: basePath,
				Value: map[string]string{
					key: value,
				},
			})
		} else {
			patch = append(patch, patchOperation{
				Op:   "add",
				Path: basePath,
				Value: map[string]string{
					key: value,
				},
			})
		}
	}
	return patch
}

func updateAnnotation(target map[string]string, added map[string]string) (patch []patchOperation) {
	for key, value := range added {
		if target == nil || target[key] == "" {
			target = map[string]string{}
			patch = append(patch, patchOperation{
				Op:   "add",
				Path: "/metadata/annotations",
				Value: map[string]string{
					key: value,
				},
			})
		} else {
			patch = append(patch, patchOperation{
				Op:    "replace",
				Path:  "/metadata/annotations/" + key,
				Value: value,
			})
		}
	}
	return patch
}

// create mutation patch for resoures
//func createPatch(pod *corev1.Pod, sidecarConfig *Config, annotations map[string]string) ([]byte, error) {
func createPatch(pod *corev1.Pod, nodeselectors map[string]string) ([]byte, error) {
	var patch []patchOperation

	patch = append(patch, updateNodeSelectors(pod.Spec.NodeSelector, nodeselectors, "/spec/nodeSelector")...)

	return json.Marshal(patch)
}

// main mutation process
func (whsvr *WebhookServer) mutate(ar *v1beta1.AdmissionReview, serviceInstanceNum int) *v1beta1.AdmissionResponse {
	req := ar.Request

	var pod corev1.Pod
	if err := json.Unmarshal(req.Object.Raw, &pod); err != nil {
		glog.Errorf("Could not unmarshal raw object: %v", err)
		return &v1beta1.AdmissionResponse{
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	}

	glog.Infof("serviceInstanceNum=%d AdmissionReview for Kind=%v Name=%v Namespace=%v UID=%v patchOperation=%v",
		serviceInstanceNum, req.Kind, req.Name, req.Namespace, req.UID, req.Operation)

	// determine whether to perform mutation
	if !mutationRequired(ignoredNamespaces, &pod.ObjectMeta) {
		glog.Infof("serviceInstanceNum=%d Skipping mutation for %s/%s due to policy check", serviceInstanceNum, pod.Namespace, pod.Name)
		return &v1beta1.AdmissionResponse{
			Allowed: true,
		}
	}

	// Workaround: https://github.com/kubernetes/kubernetes/issues/57982
	nodeselectors, ok := GetNodeLabel(req.Namespace, pod.GenerateName, pod.Labels["pod-template-hash"], serviceInstanceNum)
	if !ok {
		glog.Infof("serviceInstanceNum=%d Skipping mutation for %s/%s due to GetNodeLabel failure", serviceInstanceNum, pod.Namespace, pod.Name)
		return &v1beta1.AdmissionResponse{
			Allowed: true,
		}
	}

	patchBytes, err := createPatch(&pod, nodeselectors)
	if err != nil {
		return &v1beta1.AdmissionResponse{
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	}

	glog.Infof("serviceInstanceNum=%d AdmissionResponse: patch=%v\n", serviceInstanceNum, string(patchBytes))
	return &v1beta1.AdmissionResponse{
		Allowed: true,
		Patch:   patchBytes,
		PatchType: func() *v1beta1.PatchType {
			pt := v1beta1.PatchTypeJSONPatch
			return &pt
		}(),
	}
}

// Serve method for webhook server
func (whsvr *WebhookServer) serve(w http.ResponseWriter, r *http.Request) {

	glog.Infof("serve: serviceInstance=%d", serviceInstance)

	whsvr.Lock()
	defer whsvr.Unlock()

	serviceInstanceNum := serviceInstance
	serviceInstance++

	var body []byte
	if r.Body != nil {
		if data, err := ioutil.ReadAll(r.Body); err == nil {
			body = data
		}
	}

	if len(body) == 0 {
		glog.Error("empty body")
		http.Error(w, "empty body", http.StatusBadRequest)
		return
	}

	// verify the content type is accurate
	contentType := r.Header.Get("Content-Type")
	if contentType != "application/json" {
		glog.Errorf("Content-Type=%s, expect application/json", contentType)
		http.Error(w, "invalid Content-Type, expect `application/json`", http.StatusUnsupportedMediaType)
		return
	}

	var admissionResponse *v1beta1.AdmissionResponse
	ar := v1beta1.AdmissionReview{}
	if _, _, err := deserializer.Decode(body, nil, &ar); err != nil {
		glog.Errorf("Can't decode body: %v", err)
		admissionResponse = &v1beta1.AdmissionResponse{
			Result: &metav1.Status{
				Message: err.Error(),
			},
		}
	} else {
		admissionResponse = whsvr.mutate(&ar, serviceInstanceNum)
	}

	admissionReview := v1beta1.AdmissionReview{}
	if admissionResponse != nil {
		admissionReview.Response = admissionResponse
		if ar.Request != nil {
			admissionReview.Response.UID = ar.Request.UID
		}
	}

	resp, err := json.Marshal(admissionReview)
	if err != nil {
		glog.Errorf("Can't encode response: %v", err)
		http.Error(w, fmt.Sprintf("could not encode response: %v", err), http.StatusInternalServerError)
	}

	glog.Infof("Ready to write reponse ...")
	if _, err := w.Write(resp); err != nil {
		glog.Errorf("Can't write response: %v", err)
		http.Error(w, fmt.Sprintf("could not write response: %v", err), http.StatusInternalServerError)
	}

}

func GetNodeLabel(nameSpace string, podGenerateName string, podTemplateHash string, serviceInstanceNum int) (map[string]string, bool) {

	if err1 != nil {
		panic(err1.Error())
	}
	if err2 != nil {
		panic(err2.Error())
	}

	result := false
	nodeselectors := make(map[string]string)

	if AppLogLevel == "INFO" {
		glog.Infof("serviceInstanceNum=%d GetNodeLabel  nameSpace=%v podGenerateName=%v podTemplateHash=%v", serviceInstanceNum, nameSpace, podGenerateName, podTemplateHash)
	}

	podNameSplitList := strings.Split(podGenerateName, podTemplateHash)
	fmt.Println("")
	deploymentName := strings.Trim(podNameSplitList[0], "-")

	nodeselectors, result = ProcessDeployment(nameSpace, deploymentName, serviceInstanceNum, "CREATE")

	return nodeselectors, result

}

func ProcessDeployment(nameSpace string, deploymentName string, serviceInstanceNum int, flow string) (map[string]string, bool) {

	var numOfReplicas int

	result := true
	nodeselectors := make(map[string]string)
	deploymentAnnotations := map[string]string{}

	deploymentsClient := clientset.AppsV1().Deployments(nameSpace)
	deploymentData, getErr := deploymentsClient.Get(context.TODO(), deploymentName, metav1.GetOptions{})
	if getErr != nil {
		panic(fmt.Errorf("Failed to get latest version of Deployment: %v", getErr))
	}

	deploymentAnnotations = deploymentData.Annotations

	if strategy, ok := deploymentAnnotations["custom-pod-schedule-strategy"]; ok && strategy != "" {

		numOfReplicas = int(*deploymentData.Spec.Replicas)
		if AppLogLevel == "INFO" || AppLogLevel == "TRACE" {
			glog.Infof("flow=%s serviceInstanceNum=%d Found a deployment %s in namespace %s with total replicas %d and strategy=%s", flow, serviceInstanceNum, deploymentName, nameSpace, numOfReplicas, strategy)
		}

		if nodeLabelStrategyList, ok := GetPodsCustomSchedulingStrategyList(strategy, numOfReplicas, serviceInstanceNum); ok {
			if AppLogLevel == "INFO" || AppLogLevel == "TRACE" {
				glog.Infof("flow=%s serviceInstanceNum=%d nodeLabelStrategyList=%v", flow, serviceInstanceNum, nodeLabelStrategyList)
			}

			for _, nodeLabelStrategy := range nodeLabelStrategyList {
				if AppLogLevel == "TRACE" {
					glog.Infof("flow=%s serviceInstanceNum=%d nodeLabel=%s needs %d replicas\n", flow, serviceInstanceNum, nodeLabelStrategy.NodeLabel, nodeLabelStrategy.Replicas)
				}
				ExistingPodsList, result := GetNumOfExistingPods(nameSpace, deploymentName, nodeLabelStrategy.NodeLabel, serviceInstanceNum)
				numOfExistingPods := len(ExistingPodsList)
				if result {

					if AppLogLevel == "INFO" || AppLogLevel == "TRACE" {
						glog.Infof("flow=%s serviceInstanceNum=%d nodeLabel=%s currently runs %d pods", flow, serviceInstanceNum, nodeLabelStrategy.NodeLabel, numOfExistingPods)
					}

					if numOfExistingPods < nodeLabelStrategy.Replicas {
						if flow == "CREATE" {
							glog.Infof("flow=%s serviceInstanceNum=%d Currently running %d pods is less than expected %d, scheduling pod on nodeLabel %s", flow, serviceInstanceNum, numOfExistingPods, nodeLabelStrategy.Replicas, nodeLabelStrategy.NodeLabel)
							nodeLabelSplit := strings.Split(nodeLabelStrategy.NodeLabel, "=")

							nodeselectors[nodeLabelSplit[0]] = nodeLabelSplit[1]
							return nodeselectors, result
						}

					} else if numOfExistingPods == nodeLabelStrategy.Replicas {

						if AppLogLevel == "INFO" || AppLogLevel == "TRACE" {
							glog.Infof("flow=%s serviceInstanceNum=%d Currently running %d pods is SAME as expected %d, ignoring the nodeLabel %s", flow, serviceInstanceNum, numOfExistingPods, nodeLabelStrategy.Replicas, nodeLabelStrategy.NodeLabel)
						}

					} else {
						if flow == "DELETE" {
							numOfPodsToBeDeleted := numOfExistingPods - nodeLabelStrategy.Replicas
							glog.Infof("flow=%s serviceInstanceNum=%d Currently running %d pods is more than expected %d, So deleting %d pods on nodeLabel %s", flow, serviceInstanceNum, numOfExistingPods, nodeLabelStrategy.Replicas, numOfPodsToBeDeleted, nodeLabelStrategy.NodeLabel)
							DeleteExtraPods(nameSpace, ExistingPodsList, numOfPodsToBeDeleted)
						}
					}

				} else {
					result = false
					glog.Infof("flow=%s serviceInstanceNum=%d GetNumOfExistingPods failed. Ignoring Custom scheduling for nodeLabel=%s", flow, serviceInstanceNum, nodeLabelStrategy.NodeLabel)
				}
			}
		} else {
			result = false
			glog.Infof("flow=%s serviceInstanceNum=%d Looks like Strategy declaration is wrong. Ignoring the custom scheduling. Pls fix and re-try", flow, serviceInstanceNum)
		}
	}

	return nodeselectors, result
}

func GetPodsCustomSchedulingStrategyList(Strategy string, numOfReplicas int, serviceInstanceNum int) ([]NodeLabelStrategy, bool) {

	nodeLabelStrategyList := []NodeLabelStrategy{}

	result := true

	if AppLogLevel == "INFO" || AppLogLevel == "TRACE" {
		glog.Infof("serviceInstanceNum=%d Strategy=%s numOfReplicas=%d\n", serviceInstanceNum, Strategy, numOfReplicas)
	}

	totalWeight := 0
	replicaCount := 0

	StrategyList := strings.Split(Strategy, ":")

	numOfBaseValues := 0

	baseNodeLabel := ""

	baseNodeLabelIndex := 0

	for i, nodeStrategy := range StrategyList {

		if AppLogLevel == "TRACE" {
			fmt.Println("nodeStrategy: ", nodeStrategy)
		}

		nodeStrategyPartsList := strings.Split(nodeStrategy, ",")

		if AppLogLevel == "TRACE" {
			fmt.Println("nodeStrategyPartsList: ", nodeStrategyPartsList)
			fmt.Println("nodeStrategyPartsList len: ", len(nodeStrategyPartsList))
		}

		base := 0
		weight := 0
		nodeLabel := ""
		var err error

		for _, nodeStrategyPart := range nodeStrategyPartsList {

			nodeStrategySubPartList := strings.Split(nodeStrategyPart, "=")
			if AppLogLevel == "TRACE" {
				fmt.Println("nodeStrategyPart: ", nodeStrategyPart)
				fmt.Println("nodeStrategySubPartList: ", nodeStrategySubPartList)
				fmt.Println("nodeStrategySubPartList len: ", len(nodeStrategySubPartList))
			}

			if nodeStrategySubPartList[0] == "base" {

				if numOfBaseValues != 0 {
					fmt.Println("base value cannot be non-zero for more than node strategy")
					result = false

				} else {
					numOfBaseValues += 1
				}

				base, err = strconv.Atoi(nodeStrategySubPartList[1])
				if err != nil {
					// handle error
					fmt.Println(err)
					os.Exit(2)
				}

				if base > numOfReplicas {
					base = numOfReplicas
				}

				numOfReplicas = numOfReplicas - base

				if AppLogLevel == "TRACE" {
					fmt.Println("base=", base)
				}

			} else if nodeStrategySubPartList[0] == "weight" {

				weight, err = strconv.Atoi(nodeStrategySubPartList[1])
				if err != nil {
					// handle error
					fmt.Println(err)
					os.Exit(2)
				}
				totalWeight += weight

				if AppLogLevel == "TRACE" {
					fmt.Println("weight=", weight)
				}

			} else {
				nodeLabel = nodeStrategyPart
				if AppLogLevel == "TRACE" {
					glog.Infof("label key=%s value=%s\n", nodeStrategySubPartList[0], nodeStrategySubPartList[1])
				}
			}
		}

		if numOfBaseValues == 1 {
			if baseNodeLabel == "" {
				baseNodeLabel = nodeLabel
				baseNodeLabelIndex = i
			}
		}

		nodeLabelStrategyList = append(nodeLabelStrategyList, NodeLabelStrategy{
			NodeLabel: nodeLabel,
			Replicas:  base,
			Weight:    weight,
		})

	}

	if numOfReplicas > 0 {

		weight := nodeLabelStrategyList[baseNodeLabelIndex].Weight
		baseReplicas := nodeLabelStrategyList[baseNodeLabelIndex].Replicas
		weightReplicas := int(numOfReplicas * weight / totalWeight)
		baseReplicas = baseReplicas + weightReplicas
		replicaCount = weightReplicas

		nodeLabelStrategyList[baseNodeLabelIndex].Replicas = baseReplicas

		totalNumOfLables := len(nodeLabelStrategyList)
		if AppLogLevel == "TRACE" {
			glog.Infof("baseNodeLabel=%s baseReplicas = %v replicaCount=%v numOfReplicas=%v totalNumOfLables=%v\n", baseNodeLabel, baseReplicas, replicaCount, numOfReplicas, totalNumOfLables)
		}

		labelNum := 0

		for index, nodeLabelStrategy := range nodeLabelStrategyList {

			if index != baseNodeLabelIndex {

				if AppLogLevel == "TRACE" {
					glog.Infof("labelNum=%v nodeLabelStrategy= %v totalWeight=%v replicaCount=%v numOfReplicas=%v\n", labelNum, nodeLabelStrategy, totalWeight, replicaCount, numOfReplicas)
				}
				if labelNum == totalNumOfLables-2 {
					weightReplicas = numOfReplicas - replicaCount
				} else {

					weightReplicas = int(numOfReplicas * nodeLabelStrategy.Weight / totalWeight)
				}

				nodeLabelStrategy.Replicas += weightReplicas
				replicaCount = replicaCount + weightReplicas

				nodeLabelStrategyList[index] = nodeLabelStrategy

				if AppLogLevel == "TRACE" {
					glog.Infof("labelNum=%v weightReplicas: %v nodeLabelStrategy=%v,  replicaCount=%v, numOfReplicas=%v\n", labelNum, weightReplicas, nodeLabelStrategy, replicaCount, numOfReplicas)
				}

				labelNum += 1
			}

		}

		if AppLogLevel == "TRACE" {
			glog.Infof("nodeLabelStrategyList = %v\n", nodeLabelStrategyList)
			glog.Infof("numOfBaseValues = %v totalWeight=%v numOfReplicas=%v replicaCount=%v\n", numOfBaseValues, totalWeight, numOfReplicas, replicaCount)
		}

	}

	if AppLogLevel == "TRACE" {
		glog.Infof("nodeLabelStrategyList = %v\n", nodeLabelStrategyList)
		glog.Infof("numOfBaseValues = %v totalWeight=%v numOfReplicas=%v replicaCount=%v\n", numOfBaseValues, totalWeight, numOfReplicas, replicaCount)
	}

	return nodeLabelStrategyList, result
}

func GetNumOfExistingPods(namespace string, deploymentName string, nodeLabel string, serviceInstanceNum int) ([]string, bool) {
	result := true

	ExistingPodsList := []string{}

	if AppLogLevel == "TRACE" {
		glog.Infof("serviceInstanceNum=%d GetNumOfExistingPods namespace=%v deploymentName=%v nodeLabel=%v\n", serviceInstanceNum, namespace, deploymentName, nodeLabel)
	}
	nodeLabelSplit := strings.Split(nodeLabel, "=")

	listOptions := metav1.ListOptions{}
	//time.Sleep(1 * time.Second)
	time.Sleep(500 * time.Millisecond) // this is to give enough time for concurrent writes to etcd from other mutatting requests
	pods, err := api.Pods(namespace).List(context.Background(), listOptions)
	if err != nil {
		result = false
		log.Fatalln("failed to get pods:", err)
	}

	for _, pod := range pods.Items {

		if strings.Contains(pod.Name, deploymentName) {

			nodeSelectorMap := pod.Spec.NodeSelector

			for nodeLabelKey, nodeLabelValue := range nodeSelectorMap {
				if nodeLabelKey == nodeLabelSplit[0] && nodeLabelValue == nodeLabelSplit[1] {
					if pod.DeletionTimestamp == nil {

						ExistingPodsList = append(ExistingPodsList, pod.Name)
					}

				}
			}

		}

	}

	return ExistingPodsList, result
}

func DeleteExtraPods(nameSpace string, ExistingPodsList []string, numOfPodsToBeDeleted int) {

	for i := 0; i < numOfPodsToBeDeleted; i++ {
		podName := ExistingPodsList[i]
		glog.Infof("Deleting the pod i %d Name %s", i, podName)
		err := api.Pods(nameSpace).Delete(context.TODO(), podName, metav1.DeleteOptions{})
		if err != nil {
			log.Fatal(err)
		}
	}
}
