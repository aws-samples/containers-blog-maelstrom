#!/bin/bash

read -p "This script will clean up all resources deployed as part of the blog post. Are you sure you want to proceed (y/n)? " -n 1 -r
echo -e "\n"
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo "proceeding with clean up steps."
    echo -e "\n"
else
    exit 1
fi

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

#delete cloudwatch alarm
aws cloudwatch delete-alarms --region ${CAP_CLUSTER_REGION} --alarm-names "400 errors from ho11y app"

#schedule key for deletion
KEY_ID=$(aws kms describe-key --region ${CAP_CLUSTER_REGION} --key-id alias/${FUNCTION_NAME}-key --query KeyMetadata.KeyId --output text)
#aws kms delete-alias --region ${CAP_CLUSTER_REGION} --alias-name alias/${FUNCTION_NAME}-key
aws kms schedule-key-deletion --region ${CAP_CLUSTER_REGION} --key-id $KEY_ID --pending-window-in-days 7

#delete lambda funtion and its log group
aws lambda delete-function --region ${CAP_CLUSTER_REGION} --function-name ${FUNCTION_NAME}
aws logs delete-log-group --region ${CAP_CLUSTER_REGION} --log-group-name /aws/lambda/${FUNCTION_NAME}

#delete lambda execution role
aws iam delete-role-policy --role-name ${FUNCTION_NAME}-ExecutionRole --policy-name ${FUNCTION_NAME}-ExecutionRolePolicy
aws iam delete-role --role-name ${FUNCTION_NAME}-ExecutionRole

#delete SNS topic
aws sns delete-topic --region ${CAP_CLUSTER_REGION} --topic-arn arn:aws:sns:${CAP_CLUSTER_REGION}:${CAP_ACCOUNT_ID}:${FUNCTION_NAME}-Topic

#delete metric filter
aws logs delete-metric-filter --region ${CAP_CLUSTER_REGION} --log-group-name /aws/containerinsights/${CAP_CLUSTER_NAME}/prometheus --filter-name 'ho11y_total by http_status_code'

#delete sample application deployed
kubectl delete -f ./ho11y-app.yaml
rm ./ho11y-app.yaml

#delete ECR repository along and docker images
aws ecr delete-repository --region ${CAP_CLUSTER_REGION} --repository-name ho11y --force
docker rmi "$CAP_ACCOUNT_ID.dkr.ecr.${CAP_CLUSTER_REGION}.amazonaws.com/ho11y:latest"

#delete cloned repository of sample application
rm -fr aws-o11y-recipes

#delete EKS cluster using CDK
cdk destroy ${CAP_CLUSTER_NAME}

#delete log group
aws logs delete-log-group --region ${CAP_CLUSTER_REGION} --log-group-name /aws/containerinsights/${CAP_CLUSTER_NAME}/prometheus

#delete cluster stack
aws cloudformation delete-stack --region ${CAP_CLUSTER_REGION} --stack-name ${CAP_CLUSTER_NAME}

#delete bootstrap
BUCKET_TO_DELETE=$(aws s3 ls | grep cdk-.*"${CAP_CLUSTER_REGION}" | cut -d' ' -f3)
aws s3api delete-objects --region ${CAP_CLUSTER_REGION} --bucket ${BUCKET_TO_DELETE} --delete "$(aws s3api list-object-versions --bucket ${BUCKET_TO_DELETE} --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')"
aws s3api delete-objects --region ${CAP_CLUSTER_REGION} --bucket ${BUCKET_TO_DELETE} --delete "$(aws s3api list-object-versions --bucket ${BUCKET_TO_DELETE} --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')"
aws s3 rb --region ${CAP_CLUSTER_REGION} s3://${BUCKET_TO_DELETE} --force
aws cloudformation delete-stack --region ${CAP_CLUSTER_REGION} --stack-name CDKToolkit

