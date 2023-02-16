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

#get Slack Channel name and Incoming webhook
echo -e "\n"

urlRegex='^(https)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]\.[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]$'
read -p "Slack Incoming Webhook URL: " webhookURL
if [[ $webhookURL =~ $urlRegex ]]
then
    echo -e "${webhookURL} will be encrypted and used in lambda function."
else
    echo -e "Slack Incoming Webhook URL is invalid. Check the input value and provide a valid Webhook URL."
    exit 1
fi

scRegex='^\S{1,}$'
read -p "Slack channel name: " slackChannel
if [[ $slackChannel =~ $scRegex ]]
then
    echo -e "Notifications will be sent to Slack channel ${slackChannel}."
else
    echo -e "Slack channel name is invalid. Slack channel name should not contain any spaces."
    exit 1
fi

#generate EncryptedURL

CAP_KMS_KEY_ID=$(aws kms describe-key --region ${CAP_CLUSTER_REGION} --key-id alias/${CAP_FUNCTION_NAME}-key --query KeyMetadata.KeyId --output text)
EncryptedURL=$(aws kms encrypt --region ${CAP_CLUSTER_REGION} --key-id ${CAP_KMS_KEY_ID} --plaintext `echo ${webhookURL} | base64 -w 0` --query CiphertextBlob --output text --encryption-context LambdaFunctionName=${CAP_FUNCTION_NAME})
echo $EncryptedURL
#to verify decryption
#aws kms decrypt --region ${CAP_CLUSTER_REGION} --ciphertext-blob ${EncryptedURL} --output text --query Plaintext --encryption-context LambdaFunctionName=${CAP_FUNCTION_NAME} | base64 -d

#deploy lambda function using SAM
sam deploy --region ${CAP_CLUSTER_REGION} --template templates/sam-template.yaml --resolve-s3  --confirm-changeset --stack-name ${CAP_FUNCTION_NAME}-app --capabilities CAPABILITY_IAM --parameter-overrides "AccountID=${CAP_ACCOUNT_ID} ClusterRegion=${CAP_CLUSTER_REGION} KMSKeyID=${CAP_KMS_KEY_ID} FunctionName=${CAP_FUNCTION_NAME} EncryptedURL=${EncryptedURL}"
