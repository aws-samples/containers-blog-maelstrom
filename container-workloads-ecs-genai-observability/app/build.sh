#!/bin/bash

# Build script that uses config.json for consistent model ID across all components

set -e

# Use environment variables
export BEDROCK_MODEL_ID=${BEDROCK_MODEL_ID:-"anthropic.claude-3-sonnet-20240229-v1:0"}
export AWS_REGION=${AWS_REGION:-"us-west-2"}
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
export REPO_NAME='strands-agent-monitoring'

# Create ECR repository if it doesn't exist
if ! aws ecr describe-repositories --repository-names $REPO_NAME --region $AWS_REGION > /dev/null 2>&1; then
    echo "Creating ECR repository: $REPO_NAME"
    aws ecr create-repository --repository-name $REPO_NAME --region $AWS_REGION
else
    echo "ECR repository $REPO_NAME already exists"
fi

# Login to ECR
aws ecr get-login-password --region $AWS_REGION | docker login --username AWS --password-stdin ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

echo "Building with Model ID: $BEDROCK_MODEL_ID on Account: $AWS_ACCOUNT_ID in Region: $AWS_REGION"

# Build Docker image with build args using buildx
docker buildx build \
  --platform linux/amd64 \
  --build-arg BEDROCK_MODEL_ID="$BEDROCK_MODEL_ID" \
  --build-arg AWS_REGION="$AWS_REGION" \
  -t strands-agent-monitoring .

# Variables already set above

# Tag and push
docker tag strands-agent-monitoring:latest ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPO_NAME}:latest
docker push ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/${REPO_NAME}:latest

echo "Image built and pushed with Model ID: $BEDROCK_MODEL_ID"