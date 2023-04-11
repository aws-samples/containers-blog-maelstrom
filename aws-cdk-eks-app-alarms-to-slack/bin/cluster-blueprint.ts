#!/usr/bin/env node

import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as blueprints from '@aws-quickstart/eks-blueprints';
import { AwsForFluentBitAddOnProps } from "@aws-quickstart/eks-blueprints";
import * as iam from "aws-cdk-lib/aws-iam";

const app = new cdk.App();

const account = process.env.CAP_ACCOUNT_ID! || process.env.CDK_DEFAULT_ACCOUNT!;
const region = process.env.CAP_CLUSTER_REGION! || process.env.CDK_DEFAULT_REGION!;
const clusterName = process.env.CAP_CLUSTER_NAME!;

const logGroupName = "/aws/eks/fluentbit-cloudwatch/" + clusterName + "/workload/$kubernetes['namespace_name']"
const resource = "arn:aws:logs:" + region + ":" + account +":log-group:"+ "/aws/eks/fluentbit-cloudwatch/" + clusterName + "/workload/*" + ":*" 


const cwWritePolicy = new iam.PolicyStatement({
    actions: [
        "cloudwatch:PutMetricData",
        "logs:PutLogEvents",
        "logs:DescribeLogStreams",
        "logs:DescribeLogGroups",
        "logs:CreateLogStream",
        "logs:CreateLogGroup",
        "logs:PutRetentionPolicy"
    ],
    resources: [resource],
    effect: iam.Effect.ALLOW,
  });

//for more info on values: https://github.com/aws/eks-charts/blob/master/stable/aws-for-fluent-bit/values.yaml
const props: AwsForFluentBitAddOnProps = {
    iamPolicies: [cwWritePolicy],
    values: {
      cloudWatchLogs: {
        enabled: true,
        region: region,
        logGroupTemplate: logGroupName,
        logStreamTemplate: "$kubernetes['pod_name'].$kubernetes['container_name']",
        autoCreateGroup: true,
        logFormat: "json/emf",
        logKey: "log",
        logRetentionDays:90,
      },  
    },
  };
  

const addOns: Array<blueprints.ClusterAddOn> = [
    new blueprints.addons.AwsLoadBalancerControllerAddOn(),
    new blueprints.addons.VpcCniAddOn(),
    new blueprints.addons.CoreDnsAddOn(),
    new blueprints.addons.KubeProxyAddOn(),
    //new blueprints.addons.CertManagerAddOn(),
    //new blueprints.addons.AdotCollectorAddOn(),
    new blueprints.addons.AwsForFluentBitAddOn(props)
    //, new blueprints.addons.CloudWatchAdotAddOn({deploymentMode: blueprints.addons.cloudWatchDeploymentMode.DEPLOYMENT,
    //    metricsNameSelectors: ['apiserver_request_.*', 'container_memory_.*', 'container_threads', 'otelcol_process_.*', 'ho11y*'],
    //    podLabelRegex: 'frontend|downstream(.*)'}
    //)
];


const stack = blueprints.EksBlueprint.builder()
    .account(account)
    .region(region)
    .addOns(...addOns)
    .build(app, clusterName);
