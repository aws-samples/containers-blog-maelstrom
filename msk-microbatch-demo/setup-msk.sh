#!/bin/bash

set -e

# Variables
CLUSTER_NAME="msk-demo-cluster"
REGION="us-west-2"
ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)
VPC_ID=""
SUBNET_IDS=""

echo "Setting up MSK cluster for microbatch demo..."

# Get EKS cluster VPC and subnets
echo "Getting EKS cluster network configuration..."
EKS_CLUSTER_NAME=$(kubectl config current-context | cut -d'@' -f2 | cut -d'.' -f1)
VPC_ID=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --query 'cluster.resourcesVpcConfig.vpcId' --output text)
SUBNET_IDS=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --query 'cluster.resourcesVpcConfig.subnetIds' --output text | tr '\t' ',')

echo "VPC ID: $VPC_ID"
echo "Subnet IDs: $SUBNET_IDS"

# Create MSK security group
echo "Creating MSK security group..."
MSK_SG_ID=$(aws ec2 create-security-group \
    --group-name msk-demo-sg \
    --description "Security group for MSK demo cluster" \
    --vpc-id $VPC_ID \
    --query 'GroupId' --output text)

# Allow Kafka traffic from EKS
EKS_SG_ID=$(aws eks describe-cluster --name $EKS_CLUSTER_NAME --query 'cluster.resourcesVpcConfig.clusterSecurityGroupId' --output text)
aws ec2 authorize-security-group-ingress \
    --group-id $MSK_SG_ID \
    --protocol tcp \
    --port 9096 \
    --source-group $EKS_SG_ID

# Create MSK cluster configuration
echo "Creating MSK configuration..."
aws kafka create-configuration \
    --name msk-demo-config \
    --server-properties $(echo -n "auto.create.topics.enable=true
default.replication.factor=3
min.insync.replicas=2
num.partitions=6
log.retention.hours=24" | base64 -w 0) || true

# Create MSK cluster
echo "Creating MSK cluster (this takes 15-20 minutes)..."
aws kafka create-cluster \
    --cluster-name $CLUSTER_NAME \
    --broker-node-group-info "InstanceType=kafka.t3.small,ClientSubnets=$SUBNET_IDS,SecurityGroups=$MSK_SG_ID,StorageInfo={EbsStorageInfo={VolumeSize=100}}" \
    --kafka-version "2.8.1" \
    --number-of-broker-nodes 3 \
    --client-authentication "Sasl={Scram={Enabled=true}}" \
    --encryption-info "EncryptionInTransit={ClientBroker=TLS,InCluster=true}" \
    --enhanced-monitoring PER_BROKER

echo "MSK cluster creation initiated. Waiting for cluster to be active..."
aws kafka wait cluster-active --cluster-arn $(aws kafka list-clusters --cluster-name-filter $CLUSTER_NAME --query 'ClusterInfoList[0].ClusterArn' --output text)

# Get bootstrap servers
CLUSTER_ARN=$(aws kafka list-clusters --cluster-name-filter $CLUSTER_NAME --query 'ClusterInfoList[0].ClusterArn' --output text)
BOOTSTRAP_SERVERS=$(aws kafka get-bootstrap-brokers --cluster-arn $CLUSTER_ARN --query 'BootstrapBrokerStringSaslScram' --output text)

echo "MSK cluster created successfully!"
echo "Cluster ARN: $CLUSTER_ARN"
echo "Bootstrap Servers: $BOOTSTRAP_SERVERS"

# Create Kafka user credentials in Secrets Manager
echo "Creating Kafka credentials..."
aws secretsmanager create-secret \
    --name msk-demo-credentials \
    --description "Kafka credentials for MSK demo" \
    --secret-string '{"username":"kafka-user","password":"'$(openssl rand -base64 32)'"}' || true

# Create IAM policy for MSK access
cat > msk-policy.json << EOF
{
    "Version": "2012-10-17",
    "Statement": [
        {
            "Effect": "Allow",
            "Action": [
                "kafka:DescribeCluster",
                "kafka:GetBootstrapBrokers",
                "kafka:ListScramSecrets"
            ],
            "Resource": "$CLUSTER_ARN"
        },
        {
            "Effect": "Allow",
            "Action": [
                "secretsmanager:GetSecretValue"
            ],
            "Resource": "arn:aws:secretsmanager:$REGION:$ACCOUNT_ID:secret:msk-demo-credentials*"
        }
    ]
}
EOF

aws iam create-policy \
    --policy-name MSKProcessorPolicy \
    --policy-document file://msk-policy.json || true

# Create service account with IAM role
eksctl create iamserviceaccount \
    --name kafka-processor-sa \
    --namespace msk-microbatch-demo \
    --cluster $EKS_CLUSTER_NAME \
    --attach-policy-arn arn:aws:iam::$ACCOUNT_ID:policy/MSKProcessorPolicy \
    --approve || true

echo "Setup complete!"
echo "Update 03-secret.yaml with:"
echo "  bootstrap-servers: $BOOTSTRAP_SERVERS"
echo "  username and password from Secrets Manager"
