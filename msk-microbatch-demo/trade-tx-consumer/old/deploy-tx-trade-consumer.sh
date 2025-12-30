#!/bin/bash
set -e
set -x

# Disable AWS CLI pager
export AWS_PAGER=""

# Load environment variables
export $(grep -v '^#' ../.env | xargs)

export IMAGE_TAG="latest"
export IMAGE_NAME=${IMAGE_NAME_CONSUMER}
export IMAGE_URI="${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${IMAGE_NAME}:${IMAGE_TAG}"

# Create ECR repository (idempotent)
aws ecr describe-repositories --repository-names $IMAGE_NAME --region $AWS_REGION 2>/dev/null || \
  aws ecr create-repository --repository-name $IMAGE_NAME --region $AWS_REGION

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin $AWS_ACCOUNT_ID.dkr.ecr.$AWS_REGION.amazonaws.com

# Build and push image
docker build -t $IMAGE_NAME:$IMAGE_TAG .
docker tag $IMAGE_NAME:$IMAGE_TAG $IMAGE_URI
docker push $IMAGE_URI

# Delete existing deployment (idempotent)
kubectl delete deployment trade-tx-consumer --ignore-not-found=true

# Deploy with envsubst
envsubst < trade-tx-consumer.yaml | kubectl apply -f -

echo "Deployment complete. Check logs with: kubectl logs -l app=trade-tx-consumer"
