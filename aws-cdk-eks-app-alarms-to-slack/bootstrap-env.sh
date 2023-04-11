#!/bin/bash

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

