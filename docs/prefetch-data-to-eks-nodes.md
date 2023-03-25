# Event Driven process to prefetch data to EKS Nodes using SSM Automation


### Introduction

Benefits of Event-Driven Data Prefetching Event-driven data prefetching provides several benefits, including:

Improved performance: By fetching data in anticipation of future requests, you can reduce the latency and improve the overall user experience.

Reduced server load: By fetching data ahead of time, you can reduce the load on your servers, allowing them to handle more requests.

Increased reliability: By automating the process of fetching data, you can reduce the risk of errors and improve the reliability of your system.

In this blog, we will demonstrate the usage of AWS Systems Manager SSM Automation and State Manager to prefetch container images to your existing and newer worker nodes of your Amazon EKS Cluster.

### Solution Overview

Below is the overall architecture for setting up **Event Driven process to prefetch data to EKS Nodes using SSM Automation**
[Image: Image.jpg]The process for implementing this solution is as follows:

* The first step is to identify the image repository to fetch the container image. The container image repository could be Amazon Elastic Container Registry (Amazon ECR), DockerHub or others. For this demonstration we are using Amazon ECR as the image source.
* Next, when a container image gets pushed to Amazon ECR, an event based rule is triggered  by Amazon EventBridge to trigger an AWS SSM automation to prefetch container images from Amazon ECR to your existing Amazon EKS worker nodes.
* Whenever a newer worker node gets added to your Amazon EKS cluster, based on the tags on the worker node, Systems Manager State Manager Association on tags acts on to prefetch container images to newly created worker nodes.

### Solution Walkthrough

#### Prerequisites

To run this solution, you must have the following prerequisites:

* [AWS CLI version 2.10 or higher](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) to interact with AWS services
* [eksctl](https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html) for creating and managing your Amazon EKS cluster
* [kubectl](https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html) for running kubectl commands on your Amazon EKS cluster
* [envsubst](https://yum-info.contradodigital.com/view-package/base/gettext/) for environment variables substitution (envsubst is included in gettext package)
* [jq](https://stedolan.github.io/jq/download/) for command-line JSON processing


The source code for this blog is available in AWS-Samples on [GitHub](https://github.com/aws-samples/containers-blog-maelstrom/tree/main/prefetch-data-to-EKSnodes).

Let’s start by setting a few environment variables:

```
export EDP_AWS_REGION=us-east-1
export EDP_AWS_ACCOUNT=$(aws sts get-caller-identity --query 'Account' --output text)
export EDP_NAME=prefetching-data-automation

```

Next, lets create Amazon Elastic Container Registry repository for your AWS account :

```
aws ecr create-repository \
    --cli-input-json file://EDP-Repo.json  \
    --repository-name ${EDP_NAME}
```

Next, lets create an Amazon EKS Cluster using the below commands. Using envsubst utility we will be replacing the variables in the Yaml Config file and the eksctl CLI tool will deploy the cluster using the EDP-Cluster-Config`.yaml` file:

```
envsubst < EDP-Cluster-Config.yaml | eksctl create cluster -f -
```

Next, Build a large docker image size of approximately 1 GB to test this solution by running shell script EDP-Build-Docker-Image.sh:

```
./EDP-Build-Docker-Image.sh
```

we will create `prefetching-data-automation-role` with trust policy  EDP-Events-Trust-Policy`.json `which will be assumed by Amazon EventBridge service:

```
aws iam create-role \
    --role-name $EDP_NAME-role \
    --assume-role-policy-document file://EDP-Events-Trust-Policy.json

```

we will run the below command to replace variables in EDP-Events-Policy.json policy file by using envsubst utility and attach the policy to the above created ``prefetching-data-automation-role` :

```
aws iam put-role-policy \
    --role-name ${EDP_NAME}-role \
    --policy-name ${EDP_NAME}-policy \
    --policy-document "$(envsubst < EDP-Events-Policy.json)"
```

Next, lets create Amazon EventBridge Rule to trigger SSM Run Command on successful ECR Image push, using envsubst we will be replacing the variables in the EDP-Events-Rule.json:

```
envsubst < EDP-Events-Rule.json > EDP-Events-Rule-updated.json && aws events put-rule --cli-input-json file://EDP-Events-Rule-updated.json && rm EDP-Events-Rule-updated.json
```

Next, lets Attach the Target as AWS Systems Manager Run Command to AWS EventBridge Rule created above, using envsubst we will be replacing the variables in the EDP-Events-Target.json :

```
envsubst '$EDP_AWS_REGION $EDP_AWS_ACCOUNT $EDP_NAME' < EDP-Events-Target.json > EDP-Events-Target-updated.json && aws events put-targets --rule $EDP_NAME --cli-input-json file://EDP-Events-Target-updated.json && rm EDP-Events-Target-updated.json 
```

Next, lets create AWS Systems Manager State Manager Association for new worker nodes to prefetch container images, using envsubst we will be replacing the variables in the EDP-StateManager-Association.json:

```
envsubst '$EDP_AWS_REGION $EDP_AWS_ACCOUNT $EDP_NAME' < EDP-StateManager-Association.json > EDP-StateManager-Association-updated.json && aws ssm create-association --cli-input-json file://EDP-StateManager-Association-updated.json && rm EDP-StateManager-Association-updated.json
```

Note: Status might show failed for the AWS SSM State Manager association as there is no image present in ECR yet.

#### Validation

Now the setup is complete, let’s run some validations on the setup for Event Driven process to prefetch data to EKS Nodes,

***First test** is to verify if the container images are getting fetched to existing worker nodes automatically upon a container image push.* 

Lets run the following command to get authenticated with ECR repository and push the created container image to Amazon ECR :

```
aws ecr get-login-password \
    --region $EDP_AWS_REGION | docker login \
    --username AWS \
    --password-stdin $EDP_AWS_ACCOUNT.dkr.ecr.$EDP_AWS_REGION.amazonaws.com

```

```
docker push $EDP_AWS_ACCOUNT.dkr.ecr.$EDP_AWS_REGION.amazonaws.com/$EDP_NAME
```

Now lets check if the event rule we created on the Amazon EventBridge has been triggered. In your Amazon EventBridge console, Navigate to **TriggeredRules** under **Monitoring** tab. If there are no **FailedInvocations** datapoints, then EventBridge has delivered the event to the target successfully which in this case is AWS Systems Manager Run Command (Note: It might take 3 to 5 mins for the data points to be published in the Monitoring graphs)
[Image: Image.jpg]Next lets verify if AWS Systems Manager Run Command is triggered by Amazon EventBridge. Run the below command to see the invocations. Look for `DocumentName` which should be `AWS-RunShellScript`, `RequestedDateTime` to identify corresponding run, and then status to make sure if the Run Command executed Successfully or not.

```
aws ssm list-command-invocations \
    --details \
    --filter "[{\"key\": \"DocumentName\", \"value\": \"arn:aws:ssm:us-east-1::document/AWS-RunShellScript\"}]"

```

```
Output:

{
    "CommandInvocations": [
        {
            "CommandId": "eeb9d869-421d-488f-b1ba-ce93a69db2b0",
            "InstanceId": "i-0e1a4977c389*****",
            "InstanceName": "ip-192-168-29-214.ec2.internal",
            "Comment": "",
            "DocumentName": "arn:aws:ssm:us-east-1::document/AWS-RunShellScript",
            "DocumentVersion": "$DEFAULT",
            "RequestedDateTime": "2023-02-17T17:35:48.520000-06:00",
            "Status": "Success",
            "StatusDetails": "Success",
            .......
            .......
```

Next, lets verify if the Image has been copied in to worker node of your Amazon EKS Cluster using the below command:

```
aws ec2 describe-instances \
    --filters "Name=tag:eks:cluster-name,Values=$EDP_NAME" "Name=tag:eks:nodegroup-name,Values=nodegroup" \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text | xargs -I {} aws ssm start-session \
    --target {} \
    --document-name AWS-StartInteractiveCommand \
    --parameters "command=echo \$(curl -s http://169.254.169.254/latest/meta-data/instance-id) && sudo docker images" \
    --region $EDP_AWS_REGION
```

```
Output:

Starting session with SessionId: nbbat-0cf87cdf534*****
........
REPOSITORY                                                                 TAG                  IMAGE ID       CREATED          SIZE
0266528*****.dkr.ecr.us-east-1.amazonaws.com/prefetching-data-automation   latest               d50f7ccece64   50 minutes ago   1.23GB
.......

```

***Second Test** is to validate the container image getting copied to new worker node for any newly added Amazon EKS worker node*

Lets create new worker node as part of EKS Cluster using below command :

```
eksctl scale nodegroup \
    --cluster $EDP_NAME \
    --name nodegroup \
    --nodes 2 \
    --nodes-min 1 \
    --nodes-max 3
```

Next, lets verify if the AWS System Manager State Manager Association has been triggered and association execution is successful. Note: Please wait for for few minutes for new worker node to come up and run below command

```
aws ssm list-associations \
--association-filter-list "key=AssociationName,value=$EDP_NAME"
```

```
Output:

{
    "Associations": [
        {
            "Name": "AWS-RunShellScript",
            "AssociationId": "d9c82d84-0ceb-4f0f-a8d8-35cd67d1a66e",
......
                "AssociationStatusAggregatedCount": {
                    "Failed": 1,
                    "Success": 1
                }
            },
            "AssociationName": "prefetching-data-automation"
        }
    ]
}
```

Next, lets verify if the Image has been copied in to worker node of your Amazon EKS Cluster using the below command:

```
aws ec2 describe-instances \
    --filters "Name=tag:eks:cluster-name,Values=$EDP_NAME" "Name=tag:eks:nodegroup-name,Values=nodegroup" \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text | xargs -I {} aws ssm start-session \
    --target {} \
    --document-name AWS-StartInteractiveCommand \
    --parameters "command=echo \$(curl -s http://169.254.169.254/latest/meta-data/instance-id) && sudo docker images" \
    --region $EDP_AWS_REGION
```

```
Output:

Starting session with SessionId: nbbat-0cf87cdf5347*****
........
REPOSITORY                                                                 TAG                  IMAGE ID       CREATED          SIZE
0266528*****.dkr.ecr.us-east-1.amazonaws.com/prefetching-data-automation   latest               d50f7ccece64   50 minutes ago   1.23GB
.......
```


***Final Test** is identify the time difference for a Kubernetes pod to get to running with a Container Image pulled from Amazon ECR vs Image pulled locally

_Final Test A_*

Delete the locally cached/copied image from one of the worker nodes using the following commands

```
# Grab the instance ID
InstanceID=$(kubectl get nodes -o jsonpath='{.items[*].spec.providerID}' | awk -F/ '{print $NF}')
```

```
# SSH to the instance
aws ssm start-session \
    --target $InstanceID \
    --region $EDP_AWS_REGION
```

```
# List the locally cached image that you pushed in one of the above step
sudo su
docker images
```

```
# Delete the locally cached images
docker rmi <docker image id identified above>
```

Exit out of the SSM session

Next, lets pull the latest container image and create a Kubernetes Pod :

```
sh EDP-Pod.sh
```

```
kubectl apply -f EDP-Pod.yaml 
```

Now lets run below command to check how long it took for pod to get in to running state

```
kubectl describe pod $EDP_NAME
```

Output:

```
nbbathul@88665a1f8bb5 EDP_Working % kubectl describe pod prefetching-data-automation
Name:         prefetching-data-automation
Namespace:    default
Priority:     0
Node:         ip-192-168-19-136.ec2.internal/192.168.19.136
Start Time:   Thu, 09 Mar 2023 23:03:52 -0600
Labels:       <none>
Annotations:  kubernetes.io/psp: eks.privileged
Status:       Running
IP:           192.168.23.89
IPs:
  IP:  192.168.23.89
Containers:
  prefetching-data-automation:
    Container ID:  containerd://29579b61aaca8597bade857458e95b669ab7fca142c1e8f733cfec07d15d9d4d
    Image:         022435809194.dkr.ecr.us-east-1.amazonaws.com/prefetching-data-automation:latest
    Image ID:      022435809194.dkr.ecr.us-east-1.amazonaws.com/prefetching-data-automation@sha256:d7a93473bd682ed53acbaba18405532e6c1026c35b7d04ffc96ad89d2221736c
    Port:          <none>
    Host Port:     <none>
    Command:
      sleep
      3600
    State:          Running
      Started:      Thu, 09 Mar 2023 23:04:52 -0600
    Ready:          True
    Restart Count:  0
    Environment:    <none>
```


Next, lets also validate time take by pod to get in to running state by running below commands

```
chmod +x EDP-Get-Pod-Boot-Time.sh
```

Note: Comment line 12 and uncomment line 13 if you are running on linux kernel

```
for pod in $(kubectl get --no-headers=true pods -o name | awk -F "/" '{print $2}'); do ./EDP-Get-Pod-Boot-Time.sh $pod ; done >> EDP-Pod-Up-Time-With-Image-From-ECR.txt
```

```
cat EDP-Pod-Up-Time-With-Image-From-ECR.txt
```

Output :

```
It took 60 seconds for test to boot up
```


*_Final Test B_*

Next, delete the Kubernetes Pod, create another pod by using sample pod definition file created in above and calculated the time it took to get to running state, since the image is cached locally this time it shouldn’t take long to start the pod :


```
kubectl delete pod $EDP_NAME
kubectl apply -f EDP-Pod.yaml 
```

Now lets run below command to check how long it took for pod to get in to running state

```
kubectl describe pod $EDP_NAME
```

Output:

```
nbbathul@88665a1f8bb5 EDP_Working % kubectl describe pod prefetching-data-automation                                                                                                                        
Name:         prefetching-data-automation
Namespace:    default
Priority:     0
Node:         ip-192-168-19-136.ec2.internal/192.168.19.136
Start Time:   Thu, 09 Mar 2023 23:20:05 -0600
Labels:       <none>
Annotations:  kubernetes.io/psp: eks.privileged
Status:       Running
IP:           192.168.10.39
IPs:
  IP:  192.168.10.39
Containers:
  prefetching-data-automation:
    Container ID:  containerd://fc06a2c5f5ee7734b2a9c4fd893acd1aca7c314ba035b6a01fa9954ae48a69fb
    Image:         022435809194.dkr.ecr.us-east-1.amazonaws.com/prefetching-data-automation:latest
    Image ID:      022435809194.dkr.ecr.us-east-1.amazonaws.com/prefetching-data-automation@sha256:d7a93473bd682ed53acbaba18405532e6c1026c35b7d04ffc96ad89d2221736c
    Port:          <none>
    Host Port:     <none>
    Command:
      sleep
      3600
    State:          Running
      Started:      Thu, 09 Mar 2023 23:20:06 -0600
    Ready:          True
    Restart Count:  0
    Environment:    <none>
```


Next, lets also validate time take by pod to get in to running state by running below commands

```
for pod in $(kubectl get --no-headers=true pods -o name | awk -F "/" '{print $2}'); do ./EDP-Get-Pod-Boot-Time.sh $pod ; done >> EDP-Pod-Up-Time-With-Image-From-Workernode.txt
```

```
cat EDP-Pod-Up-Time-With-Image-From-Workernode.txt
```

Output:

```
It took 1 second for test to boot up
```


Below table shows  time it took for Pod that has been created with locally cached image is drastically less when compared to Pod that has been created with image that got pulled from ECR repository.

|Entity	|Final Test A (Created Pod by pulling image from ECR repo)	|Final Test B (Created Pod by pulling locally cached Image)	|
|---	|---	|---	|
|Pod Start Time	|23:03:52 -0600	|23:20:05 -0600	|
|Pod Running Time	|23:04:52 -0600	|23:20:06 -0600	|
|Total Time Taken	|60 Seconds	|1 Second	|

## Cleanup

```
chmod +x EDP-Cleanup.sh
```

```
./EDP-Cleanup.sh
```

## Conclusion

In this blog, we demonstrated the usage of AWS Systems Manager SSM Automation and State Manager to prefetch container images to your existing and newer worker nodes of your Amazon EKS Cluster. We clearly demonstrated a clear differentiation in run times when your container images are prefetched to worker nodes. This solution will be very effective for run machine learning, analytics and other complex containerized workloads having large container images which otherwise needs lot of time to cache locally. 
For more information, see the following references:

![Ela](images/Ela.jpg)

### Elamaran Shanmugam

Elamaran (Ela) Shanmugam is a Sr. Container Specialist Solutions Architect with Amazon Web Services. Ela is a Container, Observability and Multi-Account Architecture SME and helps AWS partners and customers to design and build scalable, secure and optimized container workloads on AWS. His passion is building and automating Infrastructure to allow customers to focus more on their business. He is based out of Tampa, Florida and you can reach him on twitter @IamElaShan

![Re](images/Re.jpg)

### Re Alvarez Parmar

In his role as Containers Specialist Solutions Architect at Amazon Web Services. Re advises engineering teams with modernizing and building distributed services in the cloud. Prior to joining AWS, he spent over 15 years as Enterprise and Software Architect. He is based out of Seattle. You can connect with him on LinkedIn linkedin.com/in/realvarez/

### Naveen Kumar Bathula






