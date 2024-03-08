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

#get Slack Channel name and Incoming webhook

urlRegex='^(https)://[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]\.[-A-Za-z0-9\+&@#/%?=~_|!:,.;]*[-A-Za-z0-9\+&@#/%=~_|]$'
read -p "Slack incoming webhook URL: " webhookURL
if [[ $webhookURL =~ $urlRegex ]]
then
    log 'O' "This webhook URL will be encrypted and used in Lambda function."
else
    log 'R' "Slack incoming webhook URL is invalid. Check the input value and provide a valid full webhook URL along with protocol https://."
    exit 1
fi

read -p "Slack channel name: " slackChannel
# scRegex='^\S{1,}$'
scRegex="[[:space:]]+"
if [[ $slackChannel =~ $scRegex ]];
then
    log 'R' "Slack channel name is invalid. Slack channel name should not contain any spaces."
    exit 1
else
    log 'O' "Notifications will be sent to Slack channel ${slackChannel}."
fi

#generate EncryptedURL
KMS_KEY_ALIAS="alias/${CAP_FUNCTION_NAME}-key"
KMS_KEY_CHECK=$(aws kms list-aliases --region ${CAP_CLUSTER_REGION} --query "length(Aliases[?AliasName=='${KMS_KEY_ALIAS}'].AliasName)")

if [[ $KMS_KEY_CHECK -eq 0 ]]
then
    log 'O' "Creating KMS Key with alias ${KMS_KEY_ALIAS}."
    CAP_KMS_KEY_ID=$(aws kms create-key --region ${CAP_CLUSTER_REGION} --description "Encryption Key for lambda function ${CAP_FUNCTION_NAME}" --key-spec SYMMETRIC_DEFAULT --key-usage ENCRYPT_DECRYPT --query KeyMetadata.KeyId --output text)
    aws kms create-alias --region ${CAP_CLUSTER_REGION} --alias-name ${KMS_KEY_ALIAS} --target-key-id $CAP_KMS_KEY_ID
else
    log 'O' "Using existing KMS Key with alias ${KMS_KEY_ALIAS}."
fi

CAP_KMS_KEY_ID=$(aws kms describe-key --region ${CAP_CLUSTER_REGION} --key-id ${KMS_KEY_ALIAS} --query KeyMetadata.KeyId --output text)
EncryptedURL=$(aws kms encrypt --region ${CAP_CLUSTER_REGION} --key-id ${CAP_KMS_KEY_ID} --plaintext `echo ${webhookURL} | base64 | tr -d '\n'` --query CiphertextBlob --output text --encryption-context LambdaFunctionName=${CAP_FUNCTION_NAME})
#to verify decryption
#aws kms decrypt --region ${CAP_CLUSTER_REGION} --ciphertext-blob ${EncryptedURL} --output text --query Plaintext --encryption-context LambdaFunctionName=${CAP_FUNCTION_NAME} | base64 -d

#deploy Lambda function using SAM
sam deploy --region ${CAP_CLUSTER_REGION} --template templates/sam-template.yaml --resolve-s3  --confirm-changeset --stack-name ${CAP_FUNCTION_NAME}-app --capabilities CAPABILITY_IAM --parameter-overrides "AccountID=${CAP_ACCOUNT_ID} ClusterRegion=${CAP_CLUSTER_REGION} KMSKeyID=${CAP_KMS_KEY_ID} FunctionName=${CAP_FUNCTION_NAME} EncryptedURL=${EncryptedURL} SlackChannel=${slackChannel}"
