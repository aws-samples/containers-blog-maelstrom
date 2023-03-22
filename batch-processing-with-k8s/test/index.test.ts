import * as cdk from '@aws-cdk/core';
import { KubernetesFileBatchConstruct } from '../src';
import '@aws-cdk/assert/jest';

test('create app', () => {
  const app = new cdk.App();
  const stack = new cdk.Stack(app);
  new KubernetesFileBatchConstruct(stack, 'EksBatchJob', {});
  expect(stack).toHaveResource('AWS::Lambda::Function');
  expect(stack).toHaveResource('AWS::CloudTrail::Trail');
  expect(stack).toHaveResource('AWS::Events::Rule');
  expect(stack).toHaveResource('AWS::EC2::VPCEndpoint');
  expect(stack).toHaveResource('AWS::IAM::Role');
  expect(stack).toHaveResource('AWS::S3::Bucket');
  expect(stack).toHaveResource('AWS::EFS::FileSystem');
  expect(stack).toHaveResource('AWS::IAM::Policy');
  expect(stack).toHaveResource('AWS::SSM::Parameter');
  expect(stack).toHaveResource('Custom::AWSCDK-EKS-HelmChart');
  expect(stack).toHaveResource('AWS::EKS::Nodegroup');
  expect(stack).toHaveResource('AWS::EC2::SecurityGroup');
  expect(stack).toHaveResource('AWS::DynamoDB::Table');
  expect(stack).toHaveResource('AWS::ElastiCache::SubnetGroup');
  expect(stack).toHaveResource('AWS::ElastiCache::ReplicationGroup');
});
