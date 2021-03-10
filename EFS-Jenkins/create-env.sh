#!/usr/bin/env bash
# This script will create an EFS PVC 
# and install AWS Load Balancer Controller

printf "Getting VPC ID: "
JOF_VPC_ID=$(aws eks describe-cluster --name jenkins-on-fargate \
  --region $JOF_REGION \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

printf "$JOF_VPC_ID\n"

printf "Gettting VPC CIDR block: "
JOF_CIDR_BLOCK=$(aws ec2 describe-vpcs --vpc-ids $JOF_VPC_ID \
  --query "Vpcs[].CidrBlock" \
  --region $JOF_REGION \
  --output text)
printf "$JOF_CIDR_BLOCK\n"

printf "Creating a security Group for EFS: "
JOF_EFS_SG_ID=$(aws ec2 create-security-group \
  --region $JOF_REGION \
  --description Jenkins-on-Fargate \
  --group-name Jenkins-on-Fargate \
  --vpc-id $JOF_VPC_ID \
  --query 'GroupId' \
  --output text)
printf "$JOF_EFS_SG_ID\n"

printf "Configuring the security group to allow ingress NFS traffic from the VPC\n"
aws ec2 authorize-security-group-ingress \
  --group-id $JOF_EFS_SG_ID \
  --protocol tcp \
  --port 2049 \
  --cidr $JOF_CIDR_BLOCK \
  --region $JOF_REGION \
  --output text

printf "Creating an EFS filesystem..."
export JOF_EFS_FS_ID=$(aws efs create-file-system \
  --creation-token Jenkins-on-Fargate \
  --performance-mode generalPurpose \
  --throughput-mode bursting \
  --region $JOF_REGION \
  --tags Key=Name,Value=JenkinsVolume \
  --encrypted \
  --output text \
  --query "FileSystemId")
printf "done\n"

printf "Waiting for 10 seconds\n"
sleep 10

printf "Creating mount targets..."
for subnet in $(aws eks describe-fargate-profile \
  --output text --cluster-name jenkins-on-fargate\
  --region $JOF_REGION  \
  --fargate-profile-name fp-default  \
  --query "fargateProfile.subnets"); \
do (aws efs create-mount-target \
  --file-system-id $JOF_EFS_FS_ID \
  --subnet-id $subnet \
  --security-group $JOF_EFS_SG_ID \
  --region $JOF_REGION --output text); \
done 
printf "done\n"

printf "Creating EFS access points..."
JOF_EFS_AP=$(aws efs create-access-point \
  --file-system-id $JOF_EFS_FS_ID \
  --posix-user Uid=1000,Gid=1000 \
  --root-directory "Path=/jenkins,CreationInfo={OwnerUid=1000,OwnerGid=1000,Permissions=777}" \
  --region $JOF_REGION \
  --query 'AccessPointId' \
  --output text)
printf "done\n"


# Create storage class, persistent volume claim
echo "
apiVersion: storage.k8s.io/v1beta1
kind: CSIDriver
metadata:
  name: efs.csi.aws.com
spec:
  attachRequired: false
---
kind: StorageClass
apiVersion: storage.k8s.io/v1
metadata:
  name: efs-sc
provisioner: efs.csi.aws.com
---
apiVersion: v1
kind: PersistentVolume
metadata:
  name: jenkins-efs-pv
spec:
  capacity:
    storage: 5Gi
  volumeMode: Filesystem
  accessModes:
    - ReadWriteMany
  persistentVolumeReclaimPolicy: Retain
  storageClassName: efs-sc
  csi:
    driver: efs.csi.aws.com
    volumeHandle: $JOF_EFS_FS_ID::$JOF_EFS_AP
---
apiVersion: v1
kind: PersistentVolumeClaim
metadata:
  name: jenkins-efs-claim
spec:
  accessModes:
    - ReadWriteMany
  storageClassName: efs-sc
  resources:
    requests:
      storage: 5Gi
" | kubectl apply -f -

# Install AWS Load Balancer Controller
printf "Associatig OIDC provider..."
eksctl utils associate-iam-oidc-provider \
  --region $JOF_REGION \
  --cluster $JOF_EKS_CLUSTER\
  --approve
printf "done\n"

printf "Downloading the IAM policy document..."
curl -Ss https://raw.githubusercontent.com/kubernetes-sigs/aws-alb-ingress-controller/v2_ga/docs/install/iam_policy.json -o iam-policy.json
printf "done\n"

printf "Creating IAM policy..."
aws iam create-policy \
  --policy-name AWSLoadBalancerControllerIAMPolicy \
  --policy-document file://iam-policy.json
printf "done\n"

printf "Creating service account..."
eksctl create iamserviceaccount \
  --attach-policy-arn=arn:aws:iam::$JOF_ACCOUNT_ID:policy/AWSLoadBalancerControllerIAMPolicy \
  --cluster=$JOF_EKS_CLUSTER \
  --namespace=kube-system \
  --name=aws-load-balancer-controller \
  --override-existing-serviceaccounts \
  --region $JOF_REGION \
  --approve
printf "done\n"

printf "Installing AWS Load Balancer Controller"
helm repo add eks https://aws.github.io/eks-charts
helm repo update &>/dev/null

kubectl apply -k "github.com/aws/eks-charts/stable/aws-load-balancer-controller//crds?ref=master"

helm upgrade -i aws-load-balancer-controller \
  eks/aws-load-balancer-controller \
  --namespace kube-system \
  --set clusterName=$JOF_EKS_CLUSTER \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set vpcId=$JOF_VPC_ID \
  --set region=$JOF_REGION
