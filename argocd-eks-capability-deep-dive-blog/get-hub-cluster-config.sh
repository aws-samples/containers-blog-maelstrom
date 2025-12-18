# !/bin/bash
# Get account ID
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

aws eks update-kubeconfig --name hub-cluster --region $AWS_REGION --alias hub-cluster
# Store the cluster ARN for later use
export AWS_EKS_HUB_CLUSTER_ARN="arn:aws:eks:$AWS_REGION:$AWS_ACCOUNT_ID:cluster/hub-cluster"
# Store the Argo CD capability IAM Role ARN
export AWS_IAM_ROLE_ARGO_CD_ARN=$(aws eks describe-capability \
  --cluster-name hub-cluster \
  --capability-name argocd \
  --region $AWS_REGION \
  --query 'capability.roleArn' \
  --output text)
# Store the Argo CD server URL
export ARGO_CD_URL=$(aws eks describe-capability \
  --cluster-name hub-cluster \
  --capability-name argocd \
  --region $AWS_REGION \
  --query 'capability.configuration.argoCd.serverUrl' \
  --output text)
echo "Argo CD Server URL: $ARGO_CD_URL"


