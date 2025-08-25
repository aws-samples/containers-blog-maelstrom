# ECS Cluster CDK Project

This CDK project creates an ECS cluster named `strands-agent-sample` in the default VPC in the us-east-1 region.

## Prerequisites

- Node.js (v16 or later)
- AWS CLI configured
- AWS CDK CLI installed globally: `npm install -g aws-cdk`

## Setup

1. Install dependencies:
```bash
npm install
```

2. Bootstrap CDK (if not done before):
```bash
cdk bootstrap
```

## Deploy

Deploy the ECS cluster:
```bash
npm run deploy
```

Or using CDK directly:
```bash
cdk deploy
```

## Destroy

Remove the ECS cluster:
```bash
npm run destroy
```

Or using CDK directly:
```bash
cdk destroy
```

## What's Created

- ECS Cluster named `strands-agent-sample`
- Container Insights enabled
- Deployed in default VPC
- Region: us-west-2

## Outputs

- `ClusterName`: The name of the ECS cluster
- `ClusterArn`: The ARN of the ECS cluster  
- `VpcId`: The ID of the default VPC