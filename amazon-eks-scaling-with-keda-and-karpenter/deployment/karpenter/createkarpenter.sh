#!/bin/bash
#*************************
# Deploy Karpenter
#*************************
## SWITCH CLUSTER CONTEXT
echo "${GREEN}=========================="
echo "${GREEN}Installing karpenter"
echo "${GREEN}=========================="

source ./deployment/environmentVariables.sh

echo "${RED}Casesenstive ${BLUE} Press Y = Proceed \n or \n N = Cancel (change context 'kubectl config use-context {context name you can check using kubectl config view}' and run script)"
read user_input
#kubectl config use-context akaasif-Isengard@${CLUSTER_NAME}.${AWS_REGION}.eksctl.io
#kubectl config current-context
#kubectl config use-context akaasif-Isengard@eks-karpenter-scale.us-west-1.eksctl.io

Entry='Y'
if [[ "$user_input" == *"$Entry"* ]]; then

if [ -z $CLUSTER_NAME ] || [ -z $KARPENTER_VERSION ] || [ -z $AWS_REGION ] || [ -z $ACCOUNT_ID ] || [ -z $TEMPOUT ];then
echo "${RED}Update values & Run environmentVariables.sh file"
exit 1;
else 
echo "${GREEN}**Installing karpenter**"
# If you have login with docker in shell  execute below first
docker logout public.ecr.aws

#Create the KarpenterNode IAM Role
echo "${GREEN}Create the KarpenterNode IAM Role"

curl -fsSL https://karpenter.sh/docs/getting-started/getting-started-with-karpenter/cloudformation.yaml  > $TEMPOUT \
&& aws cloudformation deploy \
  --stack-name "Karpenter-${CLUSTER_NAME}" \
  --template-file "${TEMPOUT}" \
  --capabilities CAPABILITY_NAMED_IAM \
  --parameter-overrides "ClusterName=${CLUSTER_NAME}" \
  --region ${AWS_REGION}


#grant access to instances using the profile to connect to the cluster. This command adds the Karpenter node role to your aws-auth configmap, 
#allowing nodes with this role to connect to the cluster.

eksctl create iamidentitymapping \
  --username system:node:{{EC2PrivateDNSName}} \
  --cluster  ${CLUSTER_NAME} \
  --arn "arn:aws:iam::${ACCOUNT_ID}:role/KarpenterNodeRole-${CLUSTER_NAME}" \
  --group system:bootstrappers \
  --group system:nodes 

echo "Verify auth Map"
kubectl describe configmap -n kube-system aws-auth

# Create KarpenterController IAM Role
echo "Create KarpenterController IAM Role"

eksctl utils associate-iam-oidc-provider --cluster ${CLUSTER_NAME} --approve

#Karpenter requires permissions like launching instances. This will create an AWS IAM Role, Kubernetes service account, 
#and associate them using IAM Roles for Service Accounts (IRSA)
echo "Map AWS IAM Role  Kubernetes service account"

eksctl create iamserviceaccount \
  --cluster "${CLUSTER_NAME}" --name karpenter --namespace karpenter \
  --role-name "Karpenter-${CLUSTER_NAME}" \
  --attach-policy-arn "arn:aws:iam::${ACCOUNT_ID}:policy/KarpenterControllerPolicy-${CLUSTER_NAME}" \
  --role-only \
  --approve

export KARPENTER_IAM_ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/Karpenter-${CLUSTER_NAME}"

#Create the EC2 Spot Linked Role
echo "Create the EC2 Spot Linked Role"
aws iam create-service-linked-role --aws-service-name spot.amazonaws.com 2> /dev/null || echo 'Already exist'

#Helm Install Karpenter
echo "Helm Install Karpenter"
export CLUSTER_ENDPOINT="$(aws eks describe-cluster --name ${CLUSTER_NAME} --query "cluster.endpoint" --output text)"

helm registry logout public.ecr.aws

helm upgrade --install karpenter oci://public.ecr.aws/karpenter/karpenter --namespace karpenter --create-namespace \
  --version ${KARPENTER_VERSION} \
  --set "serviceAccount.annotations.eks\.amazonaws\.com/role-arn=${KARPENTER_IAM_ROLE_ARN}" \
  --set "settings.clusterName=${CLUSTER_NAME}" \
  --set "settings.interruptionQueue=${CLUSTER_NAME}" \
  --set "settings.featureGates.staticCapacity=false" \
  --set controller.resources.requests.cpu=1 \
  --set controller.resources.requests.memory=1Gi \
  --set controller.resources.limits.cpu=1 \
  --set controller.resources.limits.memory=1Gi \
  --wait

#deploy NodePool & EC2NodeClass 
echo "Creating NodePool & EC2NodeClass"
cat <<EOF | envsubst | kubectl apply -f -
apiVersion: karpenter.k8s.aws/v1
kind: EC2NodeClass
metadata:
  name: default
spec:
  amiFamily: AL2
  amiSelectorTerms:
    - alias: al2@latest
  role: "KarpenterNodeRole-${CLUSTER_NAME}"
  subnetSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
  securityGroupSelectorTerms:
    - tags:
        karpenter.sh/discovery: "${CLUSTER_NAME}"
---
apiVersion: karpenter.sh/v1
kind: NodePool
metadata:
  name: default
spec:
  template:
    spec:
      requirements:
        - key: karpenter.sh/capacity-type
          operator: In
          values: ["on-demand", "spot"]
        - key: node.kubernetes.io/instance-type
          operator: In
          values: ["m5.2xlarge", "m5.4xlarge", "m5.8xlarge", "c5.2xlarge", "c5.4xlarge"]
      nodeClassRef:
        group: karpenter.k8s.aws
        kind: EC2NodeClass
        name: default
      startupTaints:
        - key: karpenter.sh/unschedulable
          value: "true"
          effect: NoSchedule
  limits:
    cpu: 2000
  disruption:
    consolidationPolicy: WhenEmpty
    consolidateAfter: 10s
EOF




echo "${GREEN}=========================="
echo "${GREEN}Karpenter Completed"
echo "${GREEN}=========================="
fi

fi