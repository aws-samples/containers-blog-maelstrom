#!/bin/bash
set -e

# Disable AWS CLI pager
export AWS_PAGER=""

echo ""
echo "=== Deploying Consumer ==="

# Load environment variables
export $(grep -v '^#' .env | xargs)

cd trade-tx-consumer

export IMAGE_NAME=${IMAGE_NAME_CONSUMER}
export IMAGE_TAG=$(date +%Y%m%d-%H%M%S)
export IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${IMAGE_NAME}:${IMAGE_TAG}"

# Create ECR repository (idempotent)
echo ""
echo "Creating ECR repository..."
echo ""
aws ecr describe-repositories --repository-names $IMAGE_NAME --region $AWS_REGION 2>/dev/null || \
  aws ecr create-repository --repository-name $IMAGE_NAME --region $AWS_REGION

# Login to ECR
echo ""
echo "Logging in to ECR..."
echo ""
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build and push
echo ""
echo "Building Docker image with tag: $IMAGE_TAG"
echo ""
docker build -t $IMAGE_NAME:$IMAGE_TAG .
docker tag $IMAGE_NAME:$IMAGE_TAG $IMAGE_URI

echo ""
echo "Pushing image to ECR..."
echo ""
docker push $IMAGE_URI

# Deploy
echo ""
echo "Deploying to Kubernetes..."
echo ""
envsubst < trade-tx-consumer.yaml | kubectl apply -f -

echo ""
echo "=== Consumer Deployed ==="
echo ""
echo "Check logs with: kubectl logs -l app=trade-tx-consumer -f"
echo ""
