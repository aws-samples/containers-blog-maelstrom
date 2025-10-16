#!/bin/bash

# VPA SQS Autoscaling Demo Setup Script
set -e

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}=== EKS VPA SQS Autoscaling Demo Setup ===${NC}"

# Get AWS account ID and region
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION=$(aws configure get region)

if [ -z "$REGION" ]; then
    REGION="us-west-2"
    echo -e "${YELLOW}No default region found, using us-west-2${NC}"
fi

echo -e "${GREEN}Account ID: ${ACCOUNT_ID}${NC}"
echo -e "${GREEN}Region: ${REGION}${NC}"

# Step 1: Create SQS Queue
echo -e "\n${GREEN}Step 1: Creating SQS Queue...${NC}"
QUEUE_URL=$(aws sqs create-queue --queue-name vpa-demo-queue --region $REGION --query QueueUrl --output text 2>/dev/null || aws sqs get-queue-url --queue-name vpa-demo-queue --region $REGION --query QueueUrl --output text)
echo -e "${GREEN}Queue URL: ${QUEUE_URL}${NC}"

# Step 2: Create IAM Policy
echo -e "\n${GREEN}Step 2: Creating IAM Policy...${NC}"
cat > sqs-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "sqs:GetQueueAttributes",
                "sqs:GetQueueUrl",
                "sqs:ReceiveMessage",
                "sqs:DeleteMessage"
            ],
            "Resource": "*"
        }
    ]
}
EOF

aws iam create-policy --policy-name eks-sqs-consumer-policy --policy-document file://sqs-policy.json --region $REGION 2>/dev/null || echo "Policy already exists"

# Step 3: Create IAM Role for Service Account
echo -e "\n${GREEN}Step 3: Creating IAM Role for Service Account...${NC}"
CLUSTER_NAME=$(kubectl config current-context | cut -d'@' -f2 | cut -d'.' -f1)
OIDC_ISSUER=$(aws eks describe-cluster --name $CLUSTER_NAME --region $REGION --query "cluster.identity.oidc.issuer" --output text)
OIDC_ID=$(echo $OIDC_ISSUER | cut -d'/' -f5)

cat > trust-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Principal": {
                "Federated": "arn:aws:iam::${ACCOUNT_ID}:oidc-provider/oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}"
            },
            "Action": "sts:AssumeRoleWithWebIdentity",
            "Condition": {
                "StringEquals": {
                    "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:sub": "system:serviceaccount:vpa-sqs-scaling-demo:sqs-consumer-sa",
                    "oidc.eks.${REGION}.amazonaws.com/id/${OIDC_ID}:aud": "sts.amazonaws.com"
                }
            }
        }
    ]
}
EOF

aws iam create-role --role-name eks-sqs-consumer-role --assume-role-policy-document file://trust-policy.json --region $REGION 2>/dev/null || echo "Role already exists"
aws iam attach-role-policy --role-name eks-sqs-consumer-role --policy-arn arn:aws:iam::${ACCOUNT_ID}:policy/eks-sqs-consumer-policy --region $REGION

# Step 4: Create ECR Repository
echo -e "\n${GREEN}Step 4: Creating ECR Repository...${NC}"
aws ecr create-repository --repository-name sqs-consumer --region $REGION 2>/dev/null || echo "Repository already exists"

# Step 5: Build and Push Docker Image
echo -e "\n${GREEN}Step 5: Building and Pushing Docker Image...${NC}"
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com
docker build -t sqs-consumer .
docker tag sqs-consumer:latest ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/sqs-consumer:latest
docker push ${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com/sqs-consumer:latest

# Step 6: Update YAML files with actual values
echo -e "\n${GREEN}Step 6: Updating YAML files with actual values...${NC}"
sed -i "s/ACCOUNT_ID/${ACCOUNT_ID}/g" *.yaml
sed -i "s/REGION/${REGION}/g" *.yaml
sed -i "s|SQS_QUEUE_URL|${QUEUE_URL}|g" *.yaml

echo -e "\n${GREEN}Setup completed successfully!${NC}"
echo -e "${YELLOW}Next steps:${NC}"
echo -e "1. Install VPA: ./install-vpa.sh"
echo -e "2. Install KEDA: ./install-keda.sh"
echo -e "3. Deploy the application: ./deploy.sh"
echo -e "4. Test scaling: ./test-scaling.sh"
