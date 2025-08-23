#!/bin/bash

# Deploy to EKS
# Usage: ./deploy.sh [docker-image-uri] [namespace]

set -e

DOCKER_IMAGE=${1:-""}
NAMESPACE=${2:-"default"}
REGION=${AWS_REGION:-"us-west-2"}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Deploying to EKS${NC}"
echo "Namespace: $NAMESPACE"
echo "Region: $REGION"

# Check if Docker image is provided
if [ -z "$DOCKER_IMAGE" ]; then
    echo -e "${RED}❌ Error: Docker image URI is required${NC}"
    echo "Usage: $0 <docker-image-uri> [namespace]"
    exit 1
fi

# Get AWS account ID
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create namespace if it doesn't exist
kubectl create namespace $NAMESPACE --dry-run=client -o yaml | kubectl apply -f -

# Generate deployment with substituted values
sed -e "s|{{ACCOUNT_ID}}|$ACCOUNT_ID|g" \
    -e "s|{{DOCKER_IMAGE}}|$DOCKER_IMAGE|g" \
    ../templates/deployment.yaml | kubectl apply -n $NAMESPACE -f -

echo -e "${GREEN}✅ Deployment successful!${NC}"