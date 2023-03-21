#!/usr/bin/env node
import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import { AwsSolutionsChecks } from 'cdk-nag'
import { Aspects } from 'aws-cdk-lib';
import { SemVarEcrWatcherAppRunnerStack } from '../lib/sem-var-ecr-watcher-app-runner-stack';

const app = new cdk.App();
Aspects.of(app).add(new AwsSolutionsChecks({ verbose: true }))
new SemVarEcrWatcherAppRunnerStack(app, 'SemVarEcrWatcherAppRunnerStack', {});