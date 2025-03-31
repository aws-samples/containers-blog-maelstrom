CLUSTER_NAME=$1

if [ -z "$CLUSTER_NAME" ]; then
  CLUSTER_NAME="ECSA-Demo-Cluster"
fi

TASK_IDS="$(aws ecs list-tasks --cluster $CLUSTER_NAME | jq -r '.taskArns[] | split("/") | last')"
TASK_JSON="$(aws ecs describe-tasks --cluster $CLUSTER_NAME --tasks $TASK_IDS)"

echo "ECS Tasks:"
echo "------------------------"
echo "$TASK_JSON" | jq -r '.tasks[] | {taskArn:.taskArn, service:(.group|split(":")|last), containerInstanceId:(.containerInstanceArn|split("/")|last), desiredStatus:.desiredStatus, lastStatus:.lastStatus, hostPort:[.containers|sort_by(.name)|.[].networkBindings[0].hostPort]}' | jq -s 'sort_by(.service,.taskArn)'

CONTAINER_INSTANCE_IDS="$(echo $TASK_JSON | jq -r '[.tasks[].containerInstanceArn | split("/") | last] | unique | .[]')"
CONTAINER_INSTANCE_JSON="$(aws ecs describe-container-instances --cluster $CLUSTER_NAME --container-instances $CONTAINER_INSTANCE_IDS)"

CONTAINER_INSTANCE_JSON2="$(echo "$CONTAINER_INSTANCE_JSON" | jq -r '.containerInstances[] | {containerInstanceId:(.containerInstanceArn|split("/")|last), instanceId:.ec2InstanceId, status:.status, agentConnected:.agentConnected, runningTasksCount:.runningTasksCount|tostring, pendingTasksCount:.pendingTasksCount}' | jq -s 'sort_by(.instanceId)')"

SSM_INSTANCE_LIST="$(echo $CONTAINER_INSTANCE_JSON | jq -r '[.containerInstances[].ec2InstanceId] | join(",")')"
SSM_INSTANCE_JSON2="$(aws ssm describe-instance-information --filters "Key=InstanceIds,Values=$SSM_INSTANCE_LIST" | jq -r '.InstanceInformationList[] | {instanceId:.InstanceId, hostIpAddress:.IPAddress}' | jq -s 'sort_by(.instanceId)')"

echo ""
echo "ECS Container Instances:"
echo "------------------------"
jq --argjson arr1 "$CONTAINER_INSTANCE_JSON2" --argjson arr2 "$SSM_INSTANCE_JSON2" -n '[$arr1 + $arr2 | group_by(.instanceId) | .[] | .[0]+.[1]]'
