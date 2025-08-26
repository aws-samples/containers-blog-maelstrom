#!/bin/bash

# Deploy Strands Agent to ECS
# Usage: ./deploy-to-ecs.sh [stack-name] [docker-image-uri]

set -e

# Configuration
STACK_NAME=${1:-"strands-agent-ecs"}
DOCKER_IMAGE=${2:-""}
CLUSTER_NAME=${3:-${CLUSTER_NAME:-"strands-agent-sample"}}
REGION=${AWS_REGION:-"us-west-2"}

# Get Bedrock model ID from environment variable or use default
BEDROCK_MODEL_ID=${4:-${BEDROCK_MODEL_ID:-"anthropic.claude-3-sonnet-20240229-v1:0"}}

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🚀 Deploying Strands Agent to ECS${NC}"
echo "Stack Name: $STACK_NAME"
echo "Cluster: $CLUSTER_NAME"
echo "Region: $REGION"
echo "Bedrock Model: $BEDROCK_MODEL_ID"

# Check if Docker image is provided
if [ -z "$DOCKER_IMAGE" ]; then
    echo -e "${RED}❌ Error: Docker image URI is required${NC}"
    echo "Usage: $0 [stack-name] <docker-image-uri>"
    echo "Example: $0 my-stack 123456789012.dkr.ecr.us-east-1.amazonaws.com/strands-agent:latest"
    exit 1
fi

echo "Docker Image: $DOCKER_IMAGE"

# Check if AWS CLI is configured
if ! aws sts get-caller-identity > /dev/null 2>&1; then
    echo -e "${RED}❌ Error: AWS CLI not configured or no valid credentials${NC}"
    exit 1
fi

# VPC and subnet configuration - auto-detect if not provided
VPC_ID=${VPC_ID:-$(aws ec2 describe-vpcs --filters "Name=is-default,Values=true" --query 'Vpcs[0].VpcId' --output text --region $REGION)}
if [ "$VPC_ID" = "None" ] || [ -z "$VPC_ID" ]; then
    VPC_ID=$(aws ec2 describe-vpcs --query 'Vpcs[0].VpcId' --output text --region $REGION)
fi

SUBNET_IDS=${SUBNET_IDS:-$(aws ec2 describe-subnets --filters "Name=vpc-id,Values=$VPC_ID" "Name=map-public-ip-on-launch,Values=true" --query 'Subnets[0:2].SubnetId' --output text --region $REGION | tr '\t' ',')}

echo "VPC ID: $VPC_ID"
echo "Subnet IDs: $SUBNET_IDS"

# Deploy CloudFormation stack
echo -e "${YELLOW}☁️  Deploying CloudFormation stack...${NC}"

aws cloudformation deploy \
    --template-file ../templates/ecs-console-deployment.yaml \
    --stack-name $STACK_NAME \
    --parameter-overrides \
        ClusterName=$CLUSTER_NAME \
        DockerImage=$DOCKER_IMAGE \
        VpcId=$VPC_ID \
        SubnetIds=$SUBNET_IDS \
        BedrockModelId="$BEDROCK_MODEL_ID" \
    --capabilities CAPABILITY_IAM \
    --region $REGION

if [ $? -eq 0 ]; then
    echo -e "${GREEN}✅ Deployment successful!${NC}"
    
    # Get service information
    echo -e "${YELLOW}📊 Getting service information...${NC}"
    
    SERVICE_NAME=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`ServiceName`].OutputValue' \
        --output text --region $REGION)
    
    LOG_GROUP=$(aws cloudformation describe-stacks \
        --stack-name $STACK_NAME \
        --query 'Stacks[0].Outputs[?OutputKey==`LogGroupName`].OutputValue' \
        --output text --region $REGION)
    
    echo -e "${GREEN}🎉 Deployment Complete!${NC}"
    echo "Service Name: $SERVICE_NAME"
    echo "Log Group: $LOG_GROUP"
    echo ""
    echo "To view logs:"
    echo "aws logs tail $LOG_GROUP --follow --region $REGION"
    echo ""
    echo "To check service status:"
    echo "aws ecs describe-services --cluster $CLUSTER_NAME --services $SERVICE_NAME --region $REGION"
    
else
    echo -e "${RED}❌ Deployment failed${NC}"
    exit 1
fi
