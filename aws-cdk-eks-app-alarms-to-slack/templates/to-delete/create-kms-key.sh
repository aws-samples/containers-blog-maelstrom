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

if [ -z "${CAP_FUNCTION_NAME}" ]; then
    echo -e "env variable CAP_FUNCTION_NAME not set"; exit 1
fi

if [ -z "${CAP_ROLE_ARN}" ]; then
    echo -e "env variable CAP_ROLE_ARN not set"; exit 1
fi

curr_dir=${PWD}

#create key policy file
sed -e "s|{{CAP_ROLE_ARN}}|${CAP_ROLE_ARN}|g; s|{{CAP_ACCOUNT_ID}}|${CAP_ACCOUNT_ID}|g; s|{{CAP_CLUSTER_REGION}}|${CAP_CLUSTER_REGION}|g; s|{{CAP_FUNCTION_NAME}}|${CAP_FUNCTION_NAME}|g" templates/kms-key-policy-template.json > kms-key-policy.json

#create kms key
CAP_KMS_KEY_ID=$(aws kms create-key --region ${CAP_CLUSTER_REGION} --description "Encryption Key for lambda function ${CAP_FUNCTION_NAME}" --key-spec SYMMETRIC_DEFAULT --key-usage ENCRYPT_DECRYPT --query KeyMetadata.KeyId --output text)

aws kms create-alias --region ${CAP_CLUSTER_REGION} --alias-name alias/${CAP_FUNCTION_NAME}-key --target-key-id ${CAP_KMS_KEY_ID}
#aws kms describe-key --region ${CAP_CLUSTER_REGION} --key-id alias/${CAP_FUNCTION_NAME}-key

CAP_KMS_KEY_ID=$(aws kms describe-key --region ${CAP_CLUSTER_REGION} --key-id alias/${CAP_FUNCTION_NAME}-key --query KeyMetadata.KeyId --output text)

aws kms put-key-policy --region ${CAP_CLUSTER_REGION} --policy-name default --key-id ${CAP_KMS_KEY_ID} --policy file://kms-key-policy.json
aws kms get-key-policy --region ${CAP_CLUSTER_REGION} --policy-name default --key-id ${CAP_KMS_KEY_ID} --output text

#deleting permission policy file
rm kms-key-policy.json
