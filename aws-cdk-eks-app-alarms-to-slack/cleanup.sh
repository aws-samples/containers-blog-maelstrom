#!/bin/bash

# exit when any command fails
set -e

read -p "This script will clean up all resources deployed as part of the blog post. Are you sure you want to proceed (y/n)? " -n 1 -r
echo -e "\n"
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo "proceeding with clean up steps."
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

#delete KMS key alias and schedule key for deletion
aws kms delete-alias --region ${CAP_CLUSTER_REGION} --alias-name alias/${FUNCTION_NAME}-key
aws kms schedule-key-deletion --region ${CAP_CLUSTER_REGION} --key-id $KEY_ID --pending-window-in-days 7

#delete lambda funtion and its log group
aws lambda delete-function --region ${CAP_CLUSTER_REGION} --function-name ${FUNCTION_NAME}
aws logs delete-log-group --region ${CAP_CLUSTER_REGION} --log-group-name /aws/lambda/${FUNCTION_NAME}

#delete lambda execution role
aws iam delete-role-policy --role-name ${FUNCTION_NAME}-ExecutionRole --policy-name ${FUNCTION_NAME}-ExecutionRolePolicy
aws iam delete-role --role-name ${FUNCTION_NAME}-ExecutionRole

#delete SNS topic
aws sns delete-topic --region ${CAP_CLUSTER_REGION} --topic-arn $SNS_TOPIC

#delete metric filter
aws logs delete-metric-filter --region ${CAP_CLUSTER_REGION} --log-group-name /aws/containerinsights/${CAP_CLUSTER_NAME}/prometheus --filter-name 'ho11y_total by http_status_code'

#delete sample application deployed
kubectl delete -f ./ho11y-app.yaml
rm ./ho11y-app.yaml

#delete ECR repository along and docker images
aws ecr delete-repository --region ${CAP_CLUSTER_REGION} --repository-name ho11y --force
docker rmi "$CAP_ACCOUNT_ID.dkr.ecr.${CAP_CLUSTER_REGION}.amazonaws.com/ho11y:latest"

#delete cloned repository of sample application
rm -r aws-o11y-recipes

#delete EKS cluster using CDK
cdk destroy ${CAP_CLUSTER_NAME}

#delete log group
aws logs delete-log-group --region ${CAP_CLUSTER_REGION} --log-group-name /aws/containerinsights/${CAP_CLUSTER_NAME}/prometheus
