CLUSTER_NAME=$1

if [ -z "$CLUSTER_NAME" ]; then
  CLUSTER_NAME="ECSA-Demo-Cluster"
fi

TARGET_GROUP_JSON="$(aws elbv2 describe-target-groups --query "TargetGroups[?starts_with(TargetGroupName,'$CLUSTER_NAME')]" | jq '[.[] | {targetGroupName:.TargetGroupName,targetGroupArn:.TargetGroupArn}]')"

TARGET_GROUP_ARN0=$(echo "$TARGET_GROUP_JSON" | jq -r ".[0].targetGroupArn")
TARGET_GROUP_ARN1=$(echo "$TARGET_GROUP_JSON" | jq -r ".[1].targetGroupArn")
TARGET_GROUP_ARN2=$(echo "$TARGET_GROUP_JSON" | jq -r ".[2].targetGroupArn")

SERVICE_JSON="$(aws ecs describe-services --cluster $CLUSTER_NAME --services Service-DemoApp1 Service-DemoApp2 | jq '[.services[] | .serviceArn]')"
SERVICE_ARN1=$(echo $SERVICE_JSON | jq -r ".[0]")
SERVICE_ARN2=$(echo $SERVICE_JSON | jq -r ".[1]")


echo "Setting Target Group Tags"
echo "------------------------"

aws ecs tag-resource --resource-arn $SERVICE_ARN1  --tags key=ecs-a.lbName,value=$TARGET_GROUP_ARN0
aws ecs tag-resource --resource-arn $SERVICE_ARN2  --tags key=ecs-a.lbName,value="$TARGET_GROUP_ARN1 $TARGET_GROUP_ARN2"

echo "DONE"
echo ""

echo "Listing Current Target Group Tags"
echo "------------------------"
echo $SERVICE_ARN1
aws ecs list-tags-for-resource --resource-arn $SERVICE_ARN1
echo ""
echo $SERVICE_ARN2
aws ecs list-tags-for-resource --resource-arn $SERVICE_ARN2
