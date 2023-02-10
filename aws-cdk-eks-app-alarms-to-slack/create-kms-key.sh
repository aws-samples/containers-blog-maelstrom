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

if [ -z "${FUNCTION_NAME}" ]; then
    echo -e "env variable FUNCTION_NAME not set"; exit 1
fi

if [ -z "${ROLE_ARN}" ]; then
    echo -e "env variable ROLE_ARN not set"; exit 1
fi

curr_dir=${PWD}

#create key policy file
sed -e "s|{{ROLE_ARN}}|${ROLE_ARN}|g; s|{{CAP_ACCOUNT_ID}}|${CAP_ACCOUNT_ID}|g; s|{{CAP_CLUSTER_REGION}}|${CAP_CLUSTER_REGION}|g; s|{{FUNCTION_NAME}}|${FUNCTION_NAME}|g" templates/kms-key-policy-template.json > kms-key-policy.json

#create kms key
KEY_ID=$(aws kms create-key --region ${CAP_CLUSTER_REGION} --key-spec SYMMETRIC_DEFAULT --key-usage ENCRYPT_DECRYPT --query KeyMetadata.KeyId --output text)

aws kms create-alias --region ${CAP_CLUSTER_REGION} --alias-name alias/${FUNCTION_NAME}-key --target-key-id $KEY_ID
aws kms describe-key --region ${CAP_CLUSTER_REGION} --key-id alias/${FUNCTION_NAME}-key

aws kms put-key-policy --region ${CAP_CLUSTER_REGION} --policy-name default --key-id $KEY_ID --policy file://kms-key-policy.json
aws kms get-key-policy --region ${CAP_CLUSTER_REGION} --policy-name default --key-id $KEY_ID --output text

#deleting permission policy file
rm kms-key-policy.json
