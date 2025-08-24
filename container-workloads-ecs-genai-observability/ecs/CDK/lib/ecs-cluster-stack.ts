import * as cdk from 'aws-cdk-lib';
import * as ecs from 'aws-cdk-lib/aws-ecs';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { Construct } from 'constructs';
import * as fs from 'fs';
import * as path from 'path';

export class EcsClusterStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props?: cdk.StackProps) {
    super(scope, id, props);

    // Use environment variables
    const region = process.env.AWS_REGION || 'us-west-2';
    const bedrockModelId = process.env.BEDROCK_MODEL_ID || 'anthropic.claude-3-haiku-20240307-v1:0';

    // Get default VPC
    const vpc = ec2.Vpc.fromLookup(this, 'DefaultVpc', {
      isDefault: true
    });

    // Create ECS Cluster
    const cluster = new ecs.Cluster(this, 'StrandsAgentCluster', {
      clusterName: 'strands-agent-sample',
      vpc: vpc,
      enableFargateCapacityProviders: true
    });

    // Enable Container Insights
    cluster.addDefaultCloudMapNamespace({
      name: 'strands-agent'
    });

    // Outputs
    new cdk.CfnOutput(this, 'ClusterName', {
      value: cluster.clusterName,
      description: 'ECS Cluster Name'
    });

    new cdk.CfnOutput(this, 'ClusterArn', {
      value: cluster.clusterArn,
      description: 'ECS Cluster ARN'
    });

    new cdk.CfnOutput(this, 'VpcId', {
      value: vpc.vpcId,
      description: 'VPC ID'
    });

    new cdk.CfnOutput(this, 'BedrockModelId', {
      value: bedrockModelId,
      description: 'Bedrock Model ID'
    });
  }
}