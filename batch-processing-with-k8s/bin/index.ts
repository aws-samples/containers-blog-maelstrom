import * as cdk from 'aws-cdk-lib';
import { KubernetesFileBatchConstruct } from '../lib/index';

const app = new cdk.App();
const env = {
  region: process.env.CDK_DEFAULT_REGION,
  account: process.env.CDK_DEFAULT_ACCOUNT,
};

const stack = new cdk.Stack(app, 'file-batch-stack', { env });

new KubernetesFileBatchConstruct(stack, 'KubernetesFileBatchConstruct', {});
