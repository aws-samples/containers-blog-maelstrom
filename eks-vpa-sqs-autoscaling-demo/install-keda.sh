#!/bin/bash

# Install KEDA
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Installing KEDA ===${NC}"

# Check if KEDA is already installed
if kubectl get deployment keda-operator -n keda >/dev/null 2>&1; then
    echo -e "${YELLOW}KEDA is already installed${NC}"
    exit 0
fi

# Add KEDA Helm repository
echo -e "${GREEN}Adding KEDA Helm repository...${NC}"
helm repo add kedacore https://kedacore.github.io/charts
helm repo update

# Install KEDA
echo -e "${GREEN}Installing KEDA...${NC}"
helm install keda kedacore/keda --namespace keda --create-namespace

# Wait for KEDA to be ready
echo -e "${GREEN}Waiting for KEDA to be ready...${NC}"
kubectl wait --for=condition=available --timeout=300s deployment/keda-operator -n keda
kubectl wait --for=condition=available --timeout=300s deployment/keda-metrics-apiserver -n keda

# Verify installation
echo -e "${GREEN}Verifying KEDA installation...${NC}"
kubectl get pods -n keda

echo -e "${GREEN}KEDA installation completed!${NC}"
