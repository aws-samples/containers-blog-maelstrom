#!/usr/bin/env node

import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as blueprints from '@aws-quickstart/eks-blueprints';
import { AdotCollectorAddOnProps, AdotCollectorAddOn, CloudWatchAdotAddOnProps } from '@aws-quickstart/eks-blueprints';
import * as iam from "aws-cdk-lib/aws-iam";
import { ControlPlaneLogType } from '@aws-quickstart/eks-blueprints';

const app = new cdk.App();

const account = process.env.CAP_ACCOUNT_ID! || process.env.CDK_DEFAULT_ACCOUNT!;
const region = process.env.CAP_CLUSTER_REGION! || process.env.CDK_DEFAULT_REGION!;
const clusterName = process.env.CAP_CLUSTER_NAME!;

const logGroupName = "/aws/eks/adot-cloudwatch/" + clusterName + "/workload/$kubernetes['namespace_name']"
const resource = "arn:aws:logs:" + region + ":" + account +":log-group:"+ "/aws/eks/adot-cloudwatch/" + clusterName + "/workload/*" + ":*" 


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

const addOns: Array<blueprints.ClusterAddOn> = [
    new blueprints.addons.AwsLoadBalancerControllerAddOn(),
    new blueprints.addons.VpcCniAddOn(),
    new blueprints.addons.CoreDnsAddOn(),
    new blueprints.addons.KubeProxyAddOn(),
    new blueprints.addons.CertManagerAddOn(),    
    new blueprints.addons.AdotCollectorAddOn(),        
  
    new blueprints.addons.CloudWatchAdotAddOn({        
        namespace: 'default',
        name: 'adot-collector-cloudwatch',
        metricsNameSelectors: ['apiserver_request_.*', 'container_memory_.*', 'container_threads', 'otelcol_process_.*'],
        podLabelRegex: 'frontend|downstream(.*)' 
    })
];
const stack = blueprints.EksBlueprint.builder()
    .account(account)
    .version('auto')
    .enableControlPlaneLogTypes(ControlPlaneLogType.API,ControlPlaneLogType.AUDIT,ControlPlaneLogType.AUTHENTICATOR,ControlPlaneLogType.CONTROLLER_MANAGER,ControlPlaneLogType.SCHEDULER)
    .region(region)
    .addOns(...addOns)
    .build(app, clusterName);



    