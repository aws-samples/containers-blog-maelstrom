#!/bin/bash

NC='\033[0m'       # Text Reset
R='\033[0;31m'          # Red
G='\033[0;32m'        # Green
Y='\033[0;33m'       # Yellow
echo -e "${Y}"

read -p "This script will clean up all resources deployed as part of the blog post. Are you sure you want to proceed [y/N]? " -n 1
if [[ $REPLY =~ ^[Yy]$ ]]
then
    echo -e "proceeding with clean up steps."
    echo -e "\n"
else
    exit 1
fi

# checking environment variables

if [ -z "${CAP_ACCOUNT_ID}" ]; then
    echo -e "${R}env variable CAP_ACCOUNT_ID not set${NC}"; exit 1
fi

if [ -z "${CAP_CLUSTER_REGION}" ]; then
    echo -e "${R}env variable CAP_CLUSTER_REGION not set${NC}"; exit 1
fi

if [ -z "${CAP_CLUSTER_NAME}" ]; then
    echo -e "${R}env variable CAP_CLUSTER_NAME not set${NC}"; exit 1
fi

if [ -z "${CAP_FUNCTION_NAME}" ]; then
    echo -e "${R}env variable CAP_FUNCTION_NAME not set${NC}"; exit 1
fi

curr_dir=${PWD}

#delete cloudwatch alarm
echo -e "${Y}deleting cloudwatch alarm${NC}"
aws cloudwatch delete-alarms --region ${CAP_CLUSTER_REGION} --alarm-names "400 errors from ho11y app"

#delete SAM app
echo -e "${Y}deleting lamdba function deployed using SAM${NC}"
sam delete --region ${CAP_CLUSTER_REGION} --stack-name ${CAP_FUNCTION_NAME}-app

#schedule key for deletion
echo -e "${Y}deleting KMS key${NC}"
CAP_KMS_KEY_ID=$(aws kms describe-key --region ${CAP_CLUSTER_REGION} --key-id alias/${CAP_FUNCTION_NAME}-key --query KeyMetadata.KeyId --output text)
aws kms delete-alias --region ${CAP_CLUSTER_REGION} --alias-name alias/${CAP_FUNCTION_NAME}-key
aws kms schedule-key-deletion --region ${CAP_CLUSTER_REGION} --key-id ${CAP_KMS_KEY_ID} --pending-window-in-days 7

#delete metric filter
echo -e "${Y}deleting metric filter${NC}"
aws logs delete-metric-filter --region ${CAP_CLUSTER_REGION} --log-group-name /aws/containerinsights/${CAP_CLUSTER_NAME}/prometheus --filter-name 'ho11y_total by http_status_code'

#delete sample application deployed
echo -e "${Y}deleting sample application ho11y${NC}"
kubectl delete -f ./ho11y-app.yaml
rm ./ho11y-app.yaml

#delete ECR repository and docker images
echo -e "${Y}deleting ECR repository and docker images${NC}"
aws ecr delete-repository --region ${CAP_CLUSTER_REGION} --repository-name ho11y --force
docker rmi "$CAP_ACCOUNT_ID.dkr.ecr.${CAP_CLUSTER_REGION}.amazonaws.com/ho11y:latest"

#delete cloned repository of sample application
echo -e "${Y}deleting cloned repository of sample application ho11y${NC}"
rm -fr aws-o11y-recipes

#delete nodegroup role which some times blocks cluster removal
echo -e "${Y}deleting nodegroup role which some times blocks cluster removal${NC}"
NGRole=$(aws cloudformation describe-stack-resources --region $CAP_CLUSTER_REGION --stack-name $CAP_CLUSTER_NAME --query 'StackResources[*].{Type:ResourceType,LogicalID:LogicalResourceId,PhysicalID:PhysicalResourceId}' --output text | grep "AWS::IAM::Role" | grep NodeGroupRole | cut -f2)
# datach role policy
for i in $(aws iam list-attached-role-policies --role-name ${NGRole} --query AttachedPolicies[*].PolicyArn[] --output text)
do
    echo -e "${Y}detaching policy $i from role ${NGRole}${NC}"
    aws iam detach-role-policy --role-name ${NGRole} --policy-arn $i
done

#delete NodeGroup Role
InstProfile=$(aws iam list-instance-profiles-for-role --role-name ${NGRole} --query InstanceProfiles[].InstanceProfileName --output text)
aws iam remove-role-from-instance-profile --instance-profile-name ${InstProfile} --role-name ${NGRole}
aws iam delete-role --role-name ${NGRole}

#delete EKS cluster using CDK
echo -e "${Y}deleting EKS cluster${NC}"
cdk destroy ${CAP_CLUSTER_NAME}

if [[ $? != 0 ]]
then
    echo -e "${R} Exiting due to error with cdk destroy.${NC}"
    exit 1
fi

#delete log groups
echo -e "${Y}deleting log groups${NC}"
aws logs delete-log-group --region ${CAP_CLUSTER_REGION} --log-group-name /aws/containerinsights/${CAP_CLUSTER_NAME}/prometheus
aws logs delete-log-group --region ${CAP_CLUSTER_REGION} --log-group-name /aws/lambda/${CAP_FUNCTION_NAME}

#delete cluster stack
echo -e "${Y}deleting CDKToolkit bootstrap${NC}"
aws cloudformation delete-stack --region ${CAP_CLUSTER_REGION} --stack-name ${CAP_CLUSTER_NAME}

#delete bootstrap
BUCKET_TO_DELETE=$(aws s3 ls | grep cdk-.*"${CAP_CLUSTER_REGION}" | cut -d' ' -f3)
aws s3api delete-objects --region ${CAP_CLUSTER_REGION} --bucket ${BUCKET_TO_DELETE} --delete "$(aws s3api list-object-versions --region ${CAP_CLUSTER_REGION} --bucket ${BUCKET_TO_DELETE} --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')"
DELETE_MARKER_COUNT=$(aws s3api list-object-versions --region ${CAP_CLUSTER_REGION} --bucket ${BUCKET_TO_DELETE} --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output text  | grep -v ^None | wc -l)
if [[ $DELETE_MARKER_COUNT > 0 ]]
then
    aws s3api delete-objects --region ${CAP_CLUSTER_REGION} --bucket ${BUCKET_TO_DELETE} --delete "$(aws s3api list-object-versions --region ${CAP_CLUSTER_REGION} --bucket ${BUCKET_TO_DELETE} --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')"
fi
aws s3 rb --region ${CAP_CLUSTER_REGION} s3://${BUCKET_TO_DELETE} --force
aws cloudformation delete-stack --region ${CAP_CLUSTER_REGION} --stack-name CDKToolkit

echo -e "${G}CLEANUP COMPLETE!!${NC}"

