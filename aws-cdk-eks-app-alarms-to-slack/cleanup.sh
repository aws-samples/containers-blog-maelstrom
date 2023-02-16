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

if [ -z "${CAP_FUNCTION_NAME}" ]; then
    echo -e "env variable CAP_FUNCTION_NAME not set"; exit 1
fi

curr_dir=${PWD}

#delete cloudwatch alarm
echo "deleting cloudwatch alarm"
aws cloudwatch delete-alarms --region ${CAP_CLUSTER_REGION} --alarm-names "400 errors from ho11y app"

#schedule key for deletion
echo "deleting KMS key"
CAP_KMS_KEY_ID=$(aws kms describe-key --region ${CAP_CLUSTER_REGION} --key-id alias/${CAP_FUNCTION_NAME}-key --query KeyMetadata.KeyId --output text)
aws kms delete-alias --region ${CAP_CLUSTER_REGION} --alias-name alias/${CAP_FUNCTION_NAME}-key
aws kms schedule-key-deletion --region ${CAP_CLUSTER_REGION} --key-id ${CAP_KMS_KEY_ID} --pending-window-in-days 7

#delete lambda funtion and its log group
echo "deleting lambda function"
aws lambda delete-function --region ${CAP_CLUSTER_REGION} --function-name ${CAP_FUNCTION_NAME}
aws logs delete-log-group --region ${CAP_CLUSTER_REGION} --log-group-name /aws/lambda/${CAP_FUNCTION_NAME}

#delete lambda execution role
echo "deleting lambda execution role"
aws iam delete-role-policy --role-name ${CAP_FUNCTION_NAME}-ExecutionRole --policy-name ${CAP_FUNCTION_NAME}-ExecutionRolePolicy
aws iam delete-role --role-name ${CAP_FUNCTION_NAME}-ExecutionRole

#delete SNS topic
echo "deleting SNS topic"
aws sns delete-topic --region ${CAP_CLUSTER_REGION} --topic-arn arn:aws:sns:${CAP_CLUSTER_REGION}:${CAP_ACCOUNT_ID}:${CAP_FUNCTION_NAME}-Topic

#delete metric filter
echo "deleting metric filter"
aws logs delete-metric-filter --region ${CAP_CLUSTER_REGION} --log-group-name /aws/containerinsights/${CAP_CLUSTER_NAME}/prometheus --filter-name 'ho11y_total by http_status_code'

#delete sample application deployed
echo "deleting sample application ho11y"
kubectl delete -f ./ho11y-app.yaml
rm ./ho11y-app.yaml

#delete ECR repository and docker images
echo "deleting ECR repository and docker images"
aws ecr delete-repository --region ${CAP_CLUSTER_REGION} --repository-name ho11y --force
docker rmi "$CAP_ACCOUNT_ID.dkr.ecr.${CAP_CLUSTER_REGION}.amazonaws.com/ho11y:latest"

#delete cloned repository of sample application
echo "deleting cloned repository of sample application ho11y"
rm -fr aws-o11y-recipes

#delete nodegroup role which some times blocks cluster removal
echo "deleting nodegroup role which some times blocks cluster removal"
NGRole=$(aws cloudformation describe-stack-resources --region $CAP_CLUSTER_REGION --stack-name $CAP_CLUSTER_NAME --query 'StackResources[*].{Type:ResourceType,LogicalID:LogicalResourceId,PhysicalID:PhysicalResourceId}' --output text | grep "AWS::IAM::Role" | grep NodeGroupRole | cut -f2)
# datach role policy
for i in $(aws iam list-attached-role-policies --role-name ${NGRole} --query AttachedPolicies[*].PolicyArn[] --output text)
do
    echo "detaching policy $i from role ${NGRole}"
    aws iam detach-role-policy --role-name ${NGRole} --policy-arn $i
done

#delete NodeGroup Role
InstProfile=$(aws iam list-instance-profiles-for-role --role-name ${NGRole} --query InstanceProfiles[].InstanceProfileName --output text)
aws iam remove-role-from-instance-profile --instance-profile-name ${InstProfile} --role-name ${NGRole}
aws iam delete-role --role-name ${NGRole}

#delete EKS cluster using CDK
echo "deleting EKS cluster"
cdk destroy ${CAP_CLUSTER_NAME}

#delete log group
aws logs delete-log-group --region ${CAP_CLUSTER_REGION} --log-group-name /aws/containerinsights/${CAP_CLUSTER_NAME}/prometheus

#delete cluster stack
echo "deleting CDKToolkit bootstrap"
aws cloudformation delete-stack --region ${CAP_CLUSTER_REGION} --stack-name ${CAP_CLUSTER_NAME}

#delete bootstrap
BUCKET_TO_DELETE=$(aws s3 ls | grep cdk-.*"${CAP_CLUSTER_REGION}" | cut -d' ' -f3)
aws s3api delete-objects --region ${CAP_CLUSTER_REGION} --bucket ${BUCKET_TO_DELETE} --delete "$(aws s3api list-object-versions --bucket ${BUCKET_TO_DELETE} --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')"
aws s3api delete-objects --region ${CAP_CLUSTER_REGION} --bucket ${BUCKET_TO_DELETE} --delete "$(aws s3api list-object-versions --bucket ${BUCKET_TO_DELETE} --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')"
aws s3 rb --region ${CAP_CLUSTER_REGION} s3://${BUCKET_TO_DELETE} --force
aws cloudformation delete-stack --region ${CAP_CLUSTER_REGION} --stack-name CDKToolkit

echo "CLEANUP COMPLETE!!"


#sam delete --region ${CAP_CLUSTER_REGION} --stack-name cloudwatch-to-slack-app
