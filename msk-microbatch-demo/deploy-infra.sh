#!/bin/bash
set -e

export TF_LOG_PROVIDER=ERROR

echo ""
echo "##### Deploying Infrastructure with Terraform #####"
echo ""

cd infra-tf

# Initialize Terraform
echo ""
echo "===== Initializing Terraform ====="
echo ""
terraform init

# Apply
echo ""
echo "===== Applying Terraform configuration ====="
echo ""
terraform apply -auto-approve

# Configure kubectl
echo ""
echo "===== Configuring kubectl ====="
echo ""
eval $(terraform output -raw configure_kubectl)
echo "✓ kubectl context updated to new EKS cluster"

# Wait for cluster to be ready
echo ""
echo "===== Waiting for cluster to be ready ====="
echo ""
kubectl wait --for=condition=Ready nodes --all --timeout=300s

# Get MSK bootstrap brokers, region, and account
export MSK_BROKERS=$(terraform output -raw msk_bootstrap_brokers_iam)
export AWS_REGION=$(terraform output -raw region)
export AWS_ACCOUNT_ID=$(terraform output -raw account_id)

cd ..

# Update .env file with MSK brokers, region, and account
grep -v "KAFKA_BOOTSTRAP_SERVERS\|AWS_REGION\|AWS_ACCOUNT_ID" .env > .env.tmp && mv .env.tmp .env
echo "AWS_REGION=$AWS_REGION" >> .env
echo "AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID" >> .env
echo "KAFKA_BOOTSTRAP_SERVERS=$MSK_BROKERS" >> .env

echo ""
echo "===== Infrastructure Deployed ====="
echo ""
echo "Next steps:"
echo ""
echo "  1. Verify .env file has correct values:"
echo "     KAFKA_BOOTSTRAP_SERVERS=$MSK_BROKERS"
echo "     AWS_REGION=$AWS_REGION"
echo "     AWS_ACCOUNT_ID=$AWS_ACCOUNT_ID"
echo ""
echo "  2. Run ./deploy-consumer.sh"
echo ""
echo "  3. Run ./deploy-producer.sh"
echo ""
