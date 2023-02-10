#!/bin/bash

# exit when any command fails
set -e

# setting environment variables
export CAP_ACCOUNT_ID=$CAP_ACCOUNT_ID || $(aws sts get-caller-identity --query 'Account' --output text)
export CAP_CLUSTER_REGION=$CAP_CLUSTER_REGION || "us-west-2"
export CAP_CLUSTER_NAME=$CAP_CLUSTER_NAME || "demo-cluster"

echo -e "\n"
echo "Following environment variables are set:"
echo "CAP_ACCOUNT_ID = "$CAP_ACCOUNT_ID
echo "CAP_CLUSTER_REGION = "$CAP_CLUSTER_REGION
echo "CAP_CLUSTER_NAME = "$CAP_CLUSTER_NAME
echo -e "\n"

# bootstrapping CDK
echo -e "bootstrapping CDK \n"
npm install
cdk bootstrap aws://$CAP_ACCOUNT_ID/$CAP_CLUSTER_REGION
