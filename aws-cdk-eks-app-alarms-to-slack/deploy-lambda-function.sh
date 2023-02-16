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

curr_dir=${PWD}

CAP_KMS_KEY_ID=$(aws kms describe-key --region ${CAP_CLUSTER_REGION} --key-id alias/${CAP_FUNCTION_NAME}-key --query KeyMetadata.KeyId --output text)

#generate EncryptedURL


#deploy lambda function using SAM
sam deploy --region ${CAP_CLUSTER_REGION} --template templates/sam-template.yaml --resolve-s3  --confirm-changeset --stack-name ${CAP_FUNCTION_NAME}-app --capabilities CAPABILITY_IAM --parameter-overrides "AccountID=${CAP_ACCOUNT_ID} ClusterRegion=${CAP_CLUSTER_REGION} KMSKeyID=${CAP_KMS_KEY_ID} FunctionName=${CAP_FUNCTION_NAME} EncryptedURL=${EncryptedURL}"
