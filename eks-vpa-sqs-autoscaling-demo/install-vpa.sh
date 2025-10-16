#!/bin/bash

# Install Vertical Pod Autoscaler
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Installing Vertical Pod Autoscaler ===${NC}"

# Check if VPA is already installed
if kubectl get deployment vpa-recommender -n kube-system >/dev/null 2>&1; then
    echo -e "${YELLOW}VPA is already installed${NC}"
    exit 0
fi

# Clone VPA repository
echo -e "${GREEN}Cloning VPA repository...${NC}"
git clone https://github.com/kubernetes/autoscaler.git /tmp/autoscaler 2>/dev/null || echo "Repository already exists"

# Install VPA
echo -e "${GREEN}Installing VPA components...${NC}"
cd /tmp/autoscaler/vertical-pod-autoscaler/
./hack/vpa-install.sh

# Verify installation
echo -e "${GREEN}Verifying VPA installation...${NC}"
kubectl get pods -n kube-system | grep vpa

echo -e "${GREEN}VPA installation completed!${NC}"
