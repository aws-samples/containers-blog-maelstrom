import * as cdk from 'aws-cdk-lib';
import { Template } from 'aws-cdk-lib/assertions';
import * as SemVarEcrWatcherAppRunner from '../lib/sem-var-ecr-watcher-app-runner-stack';

// example test. To run these tests, uncomment this file along with the
// example resource in lib/sem-var-ecr-watcher-app-runner-stack.ts
test('SQS Queue Created', () => {
   const app = new cdk.App();
    // WHEN
   const stack = new SemVarEcrWatcherAppRunner.SemVarEcrWatcherAppRunnerStack(app, 'MyTestStack');
   const template = Template.fromStack(stack);

  template.hasResource('AWS::SQS::Queue', {});
});
