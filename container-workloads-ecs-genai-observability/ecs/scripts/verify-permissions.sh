#!/bin/bash

# Verify IAM permissions for ECS deployment
# This script checks if the current AWS credentials have the necessary permissions

set -e

REGION=${AWS_REGION:-"us-west-2"}
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${GREEN}🔍 Verifying AWS permissions for ECS deployment${NC}"
echo "Region: $REGION"
echo ""

# Check AWS credentials
echo -e "${YELLOW}Checking AWS credentials...${NC}"
if aws sts get-caller-identity --region $REGION > /dev/null 2>&1; then
    ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text --region $REGION)
    USER_ARN=$(aws sts get-caller-identity --query Arn --output text --region $REGION)
    echo -e "${GREEN}✅ AWS credentials valid${NC}"
    echo "Account ID: $ACCOUNT_ID"
    echo "User/Role: $USER_ARN"
else
    echo -e "${RED}❌ AWS credentials not configured or invalid${NC}"
    exit 1
fi

echo ""

# Check ECS permissions
echo -e "${YELLOW}Checking ECS permissions...${NC}"
CLUSTER_NAME=${CLUSTER_NAME:-"strands-agent-sample"}
if aws ecs describe-clusters --clusters $CLUSTER_NAME --region $REGION > /dev/null 2>&1; then
    echo -e "${GREEN}✅ ECS cluster access verified${NC}"
else
    echo -e "${RED}❌ Cannot access ECS cluster '$CLUSTER_NAME'${NC}"
fi

# Check CloudFormation permissions
echo -e "${YELLOW}Checking CloudFormation permissions...${NC}"
if aws cloudformation list-stacks --region $REGION > /dev/null 2>&1; then
    echo -e "${GREEN}✅ CloudFormation access verified${NC}"
else
    echo -e "${RED}❌ Cannot access CloudFormation${NC}"
fi

# Check IAM permissions
echo -e "${YELLOW}Checking IAM permissions...${NC}"
if aws iam list-roles --max-items 1 --region $REGION > /dev/null 2>&1; then
    echo -e "${GREEN}✅ IAM access verified${NC}"
else
    echo -e "${RED}❌ Cannot access IAM (needed for creating task roles)${NC}"
fi

# Check Bedrock permissions
echo -e "${YELLOW}Checking Bedrock permissions...${NC}"
if aws bedrock list-foundation-models --region $REGION > /dev/null 2>&1; then
    echo -e "${GREEN}✅ Bedrock access verified${NC}"
    
    # Check specific model
    export MODEL_ID=${BEDROCK_MODEL_ID:-"anthropic.claude-3-sonnet-20240229-v1:0"}
    if aws bedrock get-foundation-model --model-identifier $MODEL_ID --region $REGION > /dev/null 2>&1; then
        echo -e "${GREEN}✅ Claude Sonnet model access verified${NC}"
    else
        echo -e "${YELLOW}⚠️  Cannot access Claude Sonnet model (may need to request access)${NC}"
    fi
else
    echo -e "${RED}❌ Cannot access Bedrock${NC}"
fi

# Check CloudWatch Logs permissions
echo -e "${YELLOW}Checking CloudWatch Logs permissions...${NC}"
if aws logs describe-log-groups --region $REGION > /dev/null 2>&1; then
    echo -e "${GREEN}✅ CloudWatch Logs access verified${NC}"
else
    echo -e "${RED}❌ Cannot access CloudWatch Logs${NC}"
fi

# Check ECR permissions
echo -e "${YELLOW}Checking ECR permissions...${NC}"
if aws ecr describe-repositories --region $REGION > /dev/null 2>&1; then
    echo -e "${GREEN}✅ ECR access verified${NC}"
else
    echo -e "${RED}❌ Cannot access ECR${NC}"
fi

echo ""
echo -e "${GREEN}🎉 Permission verification complete!${NC}"
echo ""
echo "Required IAM permissions for deployment:"
echo "- ECS: Full access to manage services and tasks"
echo "- CloudFormation: Full access to create/update stacks"
echo "- IAM: Permission to create roles and policies"
echo "- Bedrock: Access to invoke models"
echo "- CloudWatch: Access to create log groups and put metrics"
echo "- ECR: Access to push/pull Docker images"
echo "- EC2: Access to describe VPCs and subnets"
