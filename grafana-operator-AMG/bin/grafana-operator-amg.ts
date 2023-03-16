#!/usr/bin/env node

import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as blueprints from '@aws-quickstart/eks-blueprints';
import { GrafanaOperatorSecretAddon } from './grafanaoperatorsecretaddon';
import { GrafanaOperatorHelmAddon } from './grafanaoperatoryhelmaddon';

const app = new cdk.App();

const account = process.env.GO_ACCOUNT_ID! || process.env.CDK_DEFAULT_ACCOUNT!;
const region = process.env.GO_AWS_REGION! || process.env.CDK_DEFAULT_REGION!;
const clusterName = process.env.GO_CLUSTER_NAME!;
const ampWorkspaceName = process.env.GO_AMP_WORKSPACE_NAME! || 'demo-amp-Workspace';

const addOns: Array<blueprints.ClusterAddOn> = [
    new blueprints.addons.AwsLoadBalancerControllerAddOn(),
    new blueprints.addons.VpcCniAddOn(),
    new blueprints.addons.CoreDnsAddOn(),
    new blueprints.addons.KubeProxyAddOn(),
    new blueprints.addons.CertManagerAddOn(),
    new blueprints.addons.ExternalsSecretsAddOn(),
    new blueprints.addons.PrometheusNodeExporterAddOn(),
    new blueprints.addons.KubeStateMetricsAddOn(),
    new blueprints.addons.AdotCollectorAddOn(),
    new blueprints.addons.AmpAddOn({
        workspaceName: ampWorkspaceName,
    }),
    new GrafanaOperatorHelmAddon(),
    new GrafanaOperatorSecretAddon(),
    
];

const stack = blueprints.EksBlueprint.builder()
    .account(account)
    .region(region)
    .addOns(...addOns)
    .build(app, clusterName);




