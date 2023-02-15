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

curr_dir=${PWD}

#create role with trust policy
aws iam create-role --role-name ${FUNCTION_NAME}-ExecutionRole \
    --assume-role-policy-document file://templates/lambda-trust-policy.json

#get KMS Key ID
CAP_KMS_KEY_ID=$(aws kms describe-key --region ${CAP_CLUSTER_REGION} --key-id alias/${FUNCTION_NAME}-key --query KeyMetadata.KeyId --output text)

#create permission policy
sed -e "s|{{CAP_ACCOUNT_ID}}|${CAP_ACCOUNT_ID}|g; s|{{CAP_CLUSTER_REGION}}|${CAP_CLUSTER_REGION}|g; s|{{CAP_KMS_KEY_ID}}|${CAP_KMS_KEY_ID}|g; s|{{FUNCTION_NAME}}|${FUNCTION_NAME}|g" templates/lambda-permission-policy-template.json > lambda-permission-policy.json

#create role policy
aws iam put-role-policy --role-name ${FUNCTION_NAME}-ExecutionRole \
    --policy-name ${FUNCTION_NAME}-ExecutionRolePolicy \
    --policy-document file://lambda-permission-policy.json

#deleting permission policy file
rm lambda-permission-policy.json

aws iam get-role-policy --role-name ${FUNCTION_NAME}-ExecutionRole \
    --policy-name ${FUNCTION_NAME}-ExecutionRolePolicy

