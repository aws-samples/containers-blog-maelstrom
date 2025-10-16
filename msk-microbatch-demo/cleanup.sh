#!/bin/bash

echo "Cleaning up MSK microbatch demo with HPA..."

# Delete Kubernetes resources
kubectl delete namespace msk-microbatch-demo --ignore-not-found=true

# Delete MSK cluster
CLUSTER_ARN=$(aws kafka list-clusters --cluster-name-filter msk-demo-cluster --query 'ClusterInfoList[0].ClusterArn' --output text 2>/dev/null)
if [ "$CLUSTER_ARN" != "None" ] && [ "$CLUSTER_ARN" != "" ]; then
    echo "Deleting MSK cluster..."
    aws kafka delete-cluster --cluster-arn $CLUSTER_ARN
fi

# Delete security group
MSK_SG_ID=$(aws ec2 describe-security-groups --filters "Name=group-name,Values=msk-demo-sg" --query 'SecurityGroups[0].GroupId' --output text 2>/dev/null)
if [ "$MSK_SG_ID" != "None" ] && [ "$MSK_SG_ID" != "" ]; then
    echo "Deleting security group..."
    aws ec2 delete-security-group --group-id $MSK_SG_ID
fi

# Delete secrets
aws secretsmanager delete-secret --secret-id msk-demo-credentials --force-delete-without-recovery 2>/dev/null || true

# Delete IAM policy
aws iam delete-policy --policy-arn arn:aws:iam::$(aws sts get-caller-identity --query Account --output text):policy/MSKProcessorPolicy 2>/dev/null || true

# Delete ECR repository
aws ecr delete-repository --repository-name kafka-batch-processor --force 2>/dev/null || true

echo "Cleanup complete!"
