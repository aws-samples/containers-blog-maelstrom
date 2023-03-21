import { Construct } from 'constructs';
import * as events from 'aws-cdk-lib/aws-events';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as eventsources from 'aws-cdk-lib/aws-lambda-event-sources';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as s3deploy from 'aws-cdk-lib/aws-s3-deployment';
import * as sqs from 'aws-cdk-lib/aws-sqs';
import * as cdk from 'aws-cdk-lib';
import { ManagedPolicy } from 'aws-cdk-lib/aws-iam';
import { NagSuppressions } from 'cdk-nag';

export interface SemVarEcrAppRunnerConstructProps {
  readonly appRunnerServiceArn?: string;
}

export class SemVarEcrWatcherAppRunnerStack extends cdk.Stack {

  readonly appRunnerServiceArn?: string;

  constructor(scope: Construct, id: string, props: SemVarEcrAppRunnerConstructProps = {}) {
    super(scope, id);

    this.appRunnerServiceArn = props.appRunnerServiceArn ?? '';

    NagSuppressions.addStackSuppressions(this, [{
        id: 'AwsSolutions-IAM4',
        reason: 'All the required permissions are added to S3 bucket and lambda'
      }, {
        id: 'AwsSolutions-IAM5',
        reason: 'All the required permissions are added to SQS queue'
      }, {
        id: 'AwsSolutions-SQS3',
        reason: 'DLQ added, so suppressing this check.'
      }
    ])

    // Bucket to save failed records
    const semVarConfigBucket = new s3.Bucket(this, 'semvar-config-bucket', {
      removalPolicy: cdk.RemovalPolicy.DESTROY,
      autoDeleteObjects: true,
      enforceSSL: true,
      accessControl: s3.BucketAccessControl.PRIVATE,
      serverAccessLogsPrefix: 'logs',
      blockPublicAccess: s3.BlockPublicAccess.BLOCK_ALL
    });

    // Disable public access on s3 bucket
    new s3deploy.BucketDeployment(this, 'semvar-s3-deployment', {
      sources: [s3deploy.Source.asset('./config')],
      destinationBucket: semVarConfigBucket,
    });

    // SQS Queue
    const queue = new sqs.Queue(this, 'semvar-ecr-event-queue', {
      visibilityTimeout: cdk.Duration.seconds(120),
      enforceSSL: true,
      deadLetterQueue: {
        maxReceiveCount: 3,
        queue: new sqs.Queue(this, 'semvar-ecr-event-queue-dlq', {
          visibilityTimeout: cdk.Duration.seconds(120),
          enforceSSL: true,
        }),
      },
    });

    // Lambda IAM rule
    const lambdaRole = new iam.Role(this, 'semvar-lambda-role', {
      assumedBy: new iam.ServicePrincipal('lambda.amazonaws.com'),
    });

    lambdaRole.attachInlinePolicy(
      new iam.Policy(this, 'semvar-lambda-policy', {
        statements: [
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            actions: [
                "s3:GetObject",
                "s3:GetBucketLogging",
                "s3:ListBucketVersions",
                "s3:ListBucket",
                "s3:GetBucketPolicy",
                "s3:GetObjectTagging",
                "s3:GetBucketAcl",
                "s3:GetAccessPointConfigurationForObjectLambda",
                "s3:ListAllMyBuckets",
                "s3:GetBucketLocation",
                "s3:GetObjectVersion"
            ],
            resources: [`${semVarConfigBucket.bucketArn}/*`],
          }),
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            actions: [
                "sqs:ListQueues",
                "sqs:GetQueueUrl",
                "sqs:ReceiveMessage",
                "sqs:GetQueueAttributes"
            ],
            resources: [`${queue.queueArn}`],
          }),
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            actions: [
                "apprunner:DescribeService",
                "apprunner:StartDeployment",
                "apprunner:UpdateService"
            ],
            resources: ['*'],
          }),              
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            actions: ['iam:PassRole'],
            resources: ['*'],
          }),
        ],
      }),
    );

    lambdaRole.addManagedPolicy(
      ManagedPolicy.fromManagedPolicyArn(this, 'lambda-execution-role', 'arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole')
    )

    // Create lambda function
    var ecrSemVarWatcher = new lambda.DockerImageFunction(this, 'semvar-ecr-event-lambda', {
      code: lambda.DockerImageCode.fromImageAsset('./solution-code'),
      role: lambdaRole,
      environment: {
        CONFIG_BUCKET: semVarConfigBucket.bucketName,
        CONFIG_FILE: 'config.json',
        QUEUE_URL: queue.queueName,
      },
      architecture: lambda.Architecture.X86_64,
      memorySize: 2048,
      timeout: cdk.Duration.seconds(120),
    });

    // Attach Lambda to SQS
    ecrSemVarWatcher.addEventSource(new eventsources.SqsEventSource(queue));

    // IAM role to allow decrypt on KMS key
    const eventBridgeRole = new iam.Role(this, 'semvar-events-role', {
      assumedBy: new iam.ServicePrincipal('events.amazonaws.com'),
    });

    lambdaRole.attachInlinePolicy(
      new iam.Policy(this, 'semvar-events-policy', {
        statements: [
          new iam.PolicyStatement({
            effect: iam.Effect.ALLOW,
            actions: [
              'kms:Decrypt',
              'kms:GenerateDataKey',
            ],
            resources: ['*'],
          })
        ],
      }),
    );

    // Event bridge rule
    const eventBridgeRule = new events.Rule(this, 'ecr-semvar-watcher-rule', {
      eventPattern: {
        source: ['aws.ecr'],
        detailType: ['ECR Image Action'],
        detail: {
          "action-type": ['PUSH'],
          result: ['SUCCESS'],
        },
      },
    });

    // Event bridge rule target
    eventBridgeRule.addTarget(new targets.SqsQueue(queue));

    // S3 Bucket name output
    new cdk.CfnOutput(this, 'semvar-config-bucket-output', {
      exportName: 'S3-Bucket-Name',
      value: semVarConfigBucket.bucketName,
    });
  }
}
