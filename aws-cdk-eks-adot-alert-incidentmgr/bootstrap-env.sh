#!/bin/bash

#check CDK version

# Get the current version of the AWS CDK
current_version=$(cdk --version | awk '{print $1}')

# Get the latest version of the AWS CDK from the AWS CDK GitHub repository
latest_version=$(curl -s https://api.github.com/repos/aws/aws-cdk/releases/latest | grep -o '"tag_name": "[^"]*' | head -n 1 | sed 's/"tag_name": "v//')

# Compare the current version with the latest version
if [ "$current_version" != "$latest_version" ]; then
  echo "Update CDK Version"
  exit 1

# else
#   echo "AWS CDK version is up-to-date."
#   #exit 0
# fi
else
  echo "AWS CDK version is up-to-date."
  
    # exit when any command fails
    set -e

    source ./format_display.sh

    # checking environment variables

    if [ -z "${CAP_ACCOUNT_ID}" ]; then
        log 'R' "env variable CAP_ACCOUNT_ID not set"; exit 1
    fi

    if [ -z "${CAP_CLUSTER_REGION}" ]; then
        log 'R' "env variable CAP_CLUSTER_REGION not set"; exit 1
    fi

    if [ -z "${CAP_CLUSTER_NAME}" ]; then
        log 'R' "env variable CAP_CLUSTER_NAME not set"; exit 1
    fi

    if [ -z "${CAP_FUNCTION_NAME}" ]; then
        log 'R' "env variable CAP_FUNCTION_NAME not set"; exit 1
    fi

    curr_dir=${PWD}

    log 'O' "Following environment variables will be used:"
    log 'O' "CAP_ACCOUNT_ID = "$CAP_ACCOUNT_ID
    log 'O' "CAP_CLUSTER_REGION = "$CAP_CLUSTER_REGION
    log 'O' "CAP_CLUSTER_NAME = "$CAP_CLUSTER_NAME
    log 'O' "CAP_FUNCTION_NAME = "$CAP_FUNCTION_NAME

    # bootstrapping CDK
    log 'O' "bootstrapping CDK"
    npm install
    cdk bootstrap aws://${CAP_ACCOUNT_ID}/${CAP_CLUSTER_REGION}
fi

