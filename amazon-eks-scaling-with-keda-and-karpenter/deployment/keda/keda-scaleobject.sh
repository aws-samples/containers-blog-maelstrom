
echo "=====Deploy KEDA Scale Object===="

cat >./deployment/keda/kedaScaleObject.yaml <<EOF
apiVersion: keda.sh/v1alpha1
kind: ScaledObject
metadata:
  name: aws-sqs-queue-scaledobject
  namespace: ${SQS_TARGET_NAMESPACE}
spec:
  scaleTargetRef:
    name: ${SQS_TARGET_DEPLOYMENT}     #K8s deployement to target
  minReplicaCount: 0  # Scale to zero when queue is empty
  maxReplicaCount: 2000  # We don't want to have more than 15 replicas
  pollingInterval: 5 # How frequently we should go for metrics (in seconds) - faster polling
  cooldownPeriod:  5 # How many seconds should we wait for downscale - faster response
  triggers:
  - type: aws-sqs-queue
    authenticationRef:
      name: keda-aws-credentials
    metadata:
      queueURL: ${SQS_QUEUE_URL}
      queueLength: "1"  # Scale faster with 1 message per pod
      awsRegion: ${AWS_REGION}
      identityOwner: operator
---
apiVersion: keda.sh/v1alpha1
kind: TriggerAuthentication
metadata:
  name: keda-aws-credentials
  namespace: ${SQS_TARGET_NAMESPACE}
spec:
  podIdentity:
    provider: aws-eks
EOF