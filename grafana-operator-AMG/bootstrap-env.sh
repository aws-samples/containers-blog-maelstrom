#!/bin/bash

# exit when any command fails
set -e

NC='\033[0m'       # Text Reset
R='\033[0;31m'          # Red
G='\033[0;32m'        # Green
Y='\033[0;33m'       # Yellow
echo -e "${Y}"

# checking environment variables

if [ -z "${GO_ACCOUNT_ID}" ]; then
    echo -e "${R}env variable GO_ACCOUNT_ID not set${NC}"; exit 1
fi

if [ -z "${GO_AWS_REGION}" ]; then
    echo -e "${R}env variable GO_AWS_REGION not set${NC}"; exit 1
fi

if [ -z "${GO_CLUSTER_NAME}" ]; then
    echo -e "${R}env variable GO_CLUSTER_NAME not set${NC}"; exit 1
fi


curr_dir=${PWD}

echo "Following environment variables will be used:"
echo "GO_ACCOUNT_ID = "$GO_ACCOUNT_ID
echo "GO_CLUSTER_REGION = "$GO_AWS_REGION
echo "GO_CLUSTER_NAME = "$GO_CLUSTER_NAME

# bootstrapping CDK
echo -e "\n"
echo -e "bootstrapping CDK"
npm install
cdk bootstrap aws://${GO_ACCOUNT_ID}/${GO_AWS_REGION}

