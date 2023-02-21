#!/bin/bash

# exit when any command fails
set -e

NC='\033[0m'       # Text Reset
R='\033[0;31m'          # Red
G='\033[0;32m'        # Green
Y='\033[0;33m'       # Yellow
echo -e "${Y}"

# checking environment variables

if [ -z "${CAP_ACCOUNT_ID}" ]; then
    echo -e "${R}env variable CAP_ACCOUNT_ID not set${NC}"; exit 1
fi

if [ -z "${CAP_CLUSTER_REGION}" ]; then
    echo -e "${R}env variable CAP_CLUSTER_REGION not set${NC}"; exit 1
fi

if [ -z "${CAP_CLUSTER_NAME}" ]; then
    echo -e "${R}env variable CAP_CLUSTER_NAME not set${NC}"; exit 1
fi

if [ -z "${CAP_FUNCTION_NAME}" ]; then
    echo -e "${R}env variable CAP_FUNCTION_NAME not set${NC}"; exit 1
fi

curr_dir=${PWD}

echo "Following environment variables will be used:"
echo "CAP_ACCOUNT_ID = "$CAP_ACCOUNT_ID
echo "CAP_CLUSTER_REGION = "$CAP_CLUSTER_REGION
echo "CAP_CLUSTER_NAME = "$CAP_CLUSTER_NAME
echo "CAP_FUNCTION_NAME = "$CAP_FUNCTION_NAME

# bootstrapping CDK
echo -e "\n"
echo -e "bootstrapping CDK"
npm install
cdk bootstrap aws://${CAP_ACCOUNT_ID}/${CAP_CLUSTER_REGION}

