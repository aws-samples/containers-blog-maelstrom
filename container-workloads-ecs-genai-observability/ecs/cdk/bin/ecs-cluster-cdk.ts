#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { EcsClusterStack } from '../lib/ecs-cluster-stack';


const app = new cdk.App();
new EcsClusterStack(app, 'EcsClusterStack', {
  env: {
    account: process.env.CDK_DEFAULT_ACCOUNT || process.env.AWS_ACCOUNT_ID,
    region: process.env.AWS_REGION || 'us-west-2'
  }
});