#!/bin/bash

# exit when any command fails
set -e

# checking environment variables

if [ -z "${CAP_ACCOUNT_ID}" ]; then
    echo -e "env variable CAP_ACCOUNT_ID not set"; exit 1
fi

if [ -z "${CAP_CLUSTER_REGION}" ]; then
    echo -e "env variable CAP_CLUSTER_REGION not set"; exit 1
fi

if [ -z "${CAP_CLUSTER_NAME}" ]; then
    echo -e "env variable CAP_CLUSTER_NAME not set"; exit 1
fi

echo -e "\n"
echo "Following environment variables will be used:"
echo "CAP_ACCOUNT_ID = "$CAP_ACCOUNT_ID
echo "CAP_CLUSTER_REGION = "$CAP_CLUSTER_REGION
echo "CAP_CLUSTER_NAME = "$CAP_CLUSTER_NAME

# bootstrapping CDK
echo -e "\n"
echo -e "bootstrapping CDK \n"
npm install
cdk bootstrap aws://$CAP_ACCOUNT_ID/$CAP_CLUSTER_REGION

