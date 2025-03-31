CLUSTER_NAME=$1

if [ -z "$CLUSTER_NAME" ]; then
  CLUSTER_NAME="ECSA-Demo-Cluster"
fi

TARGET_GROUP_JSON="$(aws elbv2 describe-target-groups --query "TargetGroups[?starts_with(TargetGroupName,'$CLUSTER_NAME')]" | jq '[ .[] | {targetGroupName:.TargetGroupName,targetGroupArn:.TargetGroupArn,loadBalancerArn:.LoadBalancerArns[0]} ] | sort_by(.targetGroupName)')"

TARGET_GROUP_ARN0=$(echo "$TARGET_GROUP_JSON" | jq -r ".[0].targetGroupArn")
TARGET_GROUP_ARN1=$(echo "$TARGET_GROUP_JSON" | jq -r ".[1].targetGroupArn")
TARGET_GROUP_ARN2=$(echo "$TARGET_GROUP_JSON" | jq -r ".[2].targetGroupArn")


LB_ARN0=$(echo "$TARGET_GROUP_JSON" | jq -r ".[0].loadBalancerArn")
#LB_ARN1=$(echo "$TARGET_GROUP_JSON" | jq -r ".[1].loadBalancerArn")
#LB_ARN2=$(echo "$TARGET_GROUP_JSON" | jq -r ".[2].loadBalancerArn")

echo "Target Group Health"
echo "------------------------"

JQ_FILTER='.TargetHealthDescriptions[] | {target:(.Target.Id+":"+(.Target.Port|tostring)), targetHealth:{state:.TargetHealth.State,reason:.TargetHealth.Reason}}'
echo $TARGET_GROUP_ARN0
aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN0 | jq "$JQ_FILTER"
echo ""

echo $TARGET_GROUP_ARN1
aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN1 | jq "$JQ_FILTER"
echo ""

echo $TARGET_GROUP_ARN2
aws elbv2 describe-target-health --target-group-arn $TARGET_GROUP_ARN2 | jq "$JQ_FILTER"
echo ""


echo "URL"
echo "------------------------"
DNS_NAME=$(aws elbv2 describe-load-balancers --load-balancer-arns $LB_ARN0 | jq -r '.LoadBalancers[0].DNSName')
echo "http://$DNS_NAME:8080"
echo "http://$DNS_NAME:8081"
echo "http://$DNS_NAME:8082"
