#!/bin/bash

# Cleanup script for VPA SQS Demo
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Cleaning up VPA SQS Demo ===${NC}"

# Delete Kubernetes resources
echo -e "${YELLOW}Deleting Kubernetes resources...${NC}"
kubectl delete -f 05-keda-scaledobject.yaml --ignore-not-found=true
kubectl delete -f 04-vpa.yaml --ignore-not-found=true
kubectl delete -f 03-deployment.yaml --ignore-not-found=true
kubectl delete -f 02-service-account.yaml --ignore-not-found=true
kubectl delete -f 01-namespace.yaml --ignore-not-found=true

# Delete SQS queue
echo -e "${YELLOW}Deleting SQS queue...${NC}"
QUEUE_URL=$(aws sqs get-queue-url --queue-name vpa-demo-queue --query QueueUrl --output text 2>/dev/null || echo "")
if [ ! -z "$QUEUE_URL" ]; then
    aws sqs delete-queue --queue-url $QUEUE_URL
    echo -e "${GREEN}SQS queue deleted${NC}"
else
    echo -e "${YELLOW}SQS queue not found${NC}"
fi

# Delete IAM resources
echo -e "${YELLOW}Deleting IAM resources...${NC}"
aws iam detach-role-policy --role-name eks-sqs-consumer-role --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/eks-sqs-consumer-policy 2>/dev/null || echo "Policy not attached"
aws iam delete-role --role-name eks-sqs-consumer-role 2>/dev/null || echo "Role not found"
aws iam delete-policy --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/eks-sqs-consumer-policy 2>/dev/null || echo "Policy not found"

# Delete ECR repository (optional)
read -p "Delete ECR repository? (y/N): " -n 1 -r
echo
if [[ $REPLY =~ ^[Yy]$ ]]; then
    aws ecr delete-repository --repository-name sqs-consumer --force 2>/dev/null || echo "Repository not found"
    echo -e "${GREEN}ECR repository deleted${NC}"
fi

# Clean up temporary files
echo -e "${YELLOW}Cleaning up temporary files...${NC}"
rm -f sqs-policy.json trust-policy.json

echo -e "\n${GREEN}Cleanup completed!${NC}"
echo -e "${YELLOW}Note: VPA and KEDA installations were not removed. Use the following to remove them if needed:${NC}"
echo -e "- KEDA: helm uninstall keda -n keda"
echo -e "- VPA: kubectl delete -f /tmp/autoscaler/vertical-pod-autoscaler/deploy/"
