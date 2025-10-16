#!/bin/bash

set -e

ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
REGION="us-west-2"
REPO_NAME="kafka-batch-processor"

echo "Deploying MSK microbatch processor..."

# Build and push Docker image
echo "Building Docker image..."
docker build -t $REPO_NAME .

# Create ECR repository if it doesn't exist
aws ecr describe-repositories --repository-names $REPO_NAME || \
aws ecr create-repository --repository-name $REPO_NAME

# Get ECR login token
aws ecr get-login-password --region $REGION | docker login --username AWS --password-stdin $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com

# Tag and push image
docker tag $REPO_NAME:latest $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest
docker push $ACCOUNT_ID.dkr.ecr.$REGION.amazonaws.com/$REPO_NAME:latest

# Update deployment with correct image URI
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" 05-deployment.yaml
sed -i "s/REGION/$REGION/g" 05-deployment.yaml
sed -i "s/ACCOUNT_ID/$ACCOUNT_ID/g" 04-service-account.yaml

# Deploy Kubernetes resources
echo "Deploying Kubernetes resources..."
kubectl apply -f 01-namespace.yaml
kubectl apply -f 02-configmap.yaml
kubectl apply -f 03-secret.yaml
kubectl apply -f 04-service-account.yaml
kubectl apply -f 05-deployment.yaml
kubectl apply -f 06-hpa.yaml

echo "Deployment complete!"
echo "Check status with: kubectl get pods -n msk-microbatch-demo"
