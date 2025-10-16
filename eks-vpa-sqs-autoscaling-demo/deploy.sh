#!/bin/bash

# Deploy the VPA SQS Demo Application
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Deploying VPA SQS Demo Application ===${NC}"

# Apply all Kubernetes manifests
echo -e "${GREEN}Creating namespace...${NC}"
kubectl apply -f 01-namespace.yaml

echo -e "${GREEN}Creating service account...${NC}"
kubectl apply -f 02-service-account.yaml

echo -e "${GREEN}Deploying application...${NC}"
kubectl apply -f 03-deployment.yaml

echo -e "${GREEN}Creating VPA...${NC}"
kubectl apply -f 04-vpa.yaml

echo -e "${GREEN}Creating KEDA ScaledObject...${NC}"
kubectl apply -f 05-keda-scaledobject.yaml

# Wait for deployment to be ready
echo -e "${GREEN}Waiting for deployment to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/sqs-consumer -n vpa-sqs-scaling-demo

# Show status
echo -e "\n${GREEN}=== Deployment Status ===${NC}"
kubectl get pods -n vpa-sqs-scaling-demo
kubectl get vpa -n vpa-sqs-scaling-demo
kubectl get scaledobject -n vpa-sqs-scaling-demo

echo -e "\n${GREEN}Deployment completed successfully!${NC}"
echo -e "${YELLOW}Use './test-scaling.sh' to test the scaling behavior${NC}"
