#!/bin/bash
source ./format_display.sh

echo -e "\033[0;31m" # Red text
read -p "This script will clean up all resources deployed as part of the blog post. Are you sure you want to proceed [y/N]? " -n 2
echo
if [[ $REPLY =~ ^[Yy]$ ]]
then
    log 'R' "proceeding with clean up steps."
else
    exit 1
fi

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

#delete cloudwatch alarm
log 'O' "deleting cloudwatch alarm"
aws cloudwatch delete-alarms --region ${CAP_CLUSTER_REGION} --alarm-names "400 errors from sample app"

#delete SAM app
log 'O' "deleting lamdba function deployed using SAM"
sam delete --region ${CAP_CLUSTER_REGION} --stack-name ${CAP_FUNCTION_NAME}-app

#schedule key for deletion
log 'O' "deleting KMS key"
CAP_KMS_KEY_ID=$(aws kms describe-key --region ${CAP_CLUSTER_REGION} --key-id alias/${CAP_FUNCTION_NAME}-key --query KeyMetadata.KeyId --output text)
aws kms delete-alias --region ${CAP_CLUSTER_REGION} --alias-name alias/${CAP_FUNCTION_NAME}-key
aws kms schedule-key-deletion --region ${CAP_CLUSTER_REGION} --key-id ${CAP_KMS_KEY_ID} --pending-window-in-days 7

#delete metric filter
log 'O' "deleting metric filter"
aws logs delete-metric-filter --region ${CAP_CLUSTER_REGION} --log-group-name /aws/eks/fluentbit-cloudwatch/${CAP_CLUSTER_NAME}/workload/sample-app --filter-name 'Counts by Status Code'

#delete sample application deployed
log 'O' "deleting sample application"
kubectl delete -f ./templates/sample-app.yaml

#delete nodegroup role which some times blocks cluster removal
log 'O' "deleting nodegroup role which some times blocks cluster removal"
NGRole=$(aws cloudformation describe-stack-resources --region $CAP_CLUSTER_REGION --stack-name $CAP_CLUSTER_NAME --query 'StackResources[*].{Type:ResourceType,LogicalID:LogicalResourceId,PhysicalID:PhysicalResourceId}' --output text | grep "AWS::IAM::Role" | grep NodeGroupRole | cut -f2)
# datach role policy
for i in $(aws iam list-attached-role-policies --role-name ${NGRole} --query AttachedPolicies[*].PolicyArn[] --output text)
do
    log 'O' "detaching policy $i from role ${NGRole}"
    aws iam detach-role-policy --role-name ${NGRole} --policy-arn $i
done

#delete NodeGroup Role
InstProfile=$(aws iam list-instance-profiles-for-role --role-name ${NGRole} --query InstanceProfiles[].InstanceProfileName --output text)
aws iam remove-role-from-instance-profile --instance-profile-name ${InstProfile} --role-name ${NGRole}
aws iam delete-role --role-name ${NGRole}

#delete EKS cluster using CDK
log 'O' "deleting EKS cluster"
cdk destroy ${CAP_CLUSTER_NAME}

if [[ $? != 0 ]]
then
    log 'R' " Exiting due to error with cdk destroy."
    exit 1
fi

#delete log groups
log 'O' "deleting log groups"
aws logs delete-log-group --region ${CAP_CLUSTER_REGION} --log-group-name /aws/containerinsights/${CAP_CLUSTER_NAME}/prometheus
aws logs delete-log-group --region ${CAP_CLUSTER_REGION} --log-group-name /aws/lambda/${CAP_FUNCTION_NAME}

for logGroupName in $(aws logs describe-log-groups --region us-west-2 --query 'logGroups[?starts_with(logGroupName,`/aws/eks/fluentbit-cloudwatch/demo-cluster/workload`)].logGroupName' --output text); do
    aws logs delete-log-group --region ${CAP_CLUSTER_REGION} --log-group-name $logGroupName
done

#delete cluster stack
aws cloudformation delete-stack --region ${CAP_CLUSTER_REGION} --stack-name ${CAP_CLUSTER_NAME}

#delete cluster CDKToolkit bootstrp
log 'O' "deleting CDKToolkit bootstrap"

#delete bootstrap
BUCKET_TO_DELETE=$(aws s3 ls | grep cdk-.*"${CAP_CLUSTER_REGION}" | cut -d' ' -f3)
if [[ ! -z $BUCKET_TO_DELETE ]]
then
    OBJECT_COUNT=$(aws s3api list-object-versions --region ${CAP_CLUSTER_REGION} --bucket ${BUCKET_TO_DELETE} --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}' --output text | grep -v ^None | wc -l)
    if [[ $OBJECT_COUNT > 0 ]]
    then
        aws s3api delete-objects --region ${CAP_CLUSTER_REGION} --bucket ${BUCKET_TO_DELETE} --delete "$(aws s3api list-object-versions --region ${CAP_CLUSTER_REGION} --bucket ${BUCKET_TO_DELETE} --query='{Objects: Versions[].{Key:Key,VersionId:VersionId}}')"
    fi

    DELETE_MARKER_COUNT=$(aws s3api list-object-versions --region ${CAP_CLUSTER_REGION} --bucket ${BUCKET_TO_DELETE} --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}' --output text  | grep -v ^None | wc -l)
    if [[ $DELETE_MARKER_COUNT > 0 ]]
    then
        aws s3api delete-objects --region ${CAP_CLUSTER_REGION} --bucket ${BUCKET_TO_DELETE} --delete "$(aws s3api list-object-versions --region ${CAP_CLUSTER_REGION} --bucket ${BUCKET_TO_DELETE} --query='{Objects: DeleteMarkers[].{Key:Key,VersionId:VersionId}}')"
    fi

    aws s3 rb --region ${CAP_CLUSTER_REGION} s3://${BUCKET_TO_DELETE} --force
fi

aws cloudformation delete-stack --region ${CAP_CLUSTER_REGION} --stack-name CDKToolkit

log 'G' "CLEANUP COMPLETE!!"

