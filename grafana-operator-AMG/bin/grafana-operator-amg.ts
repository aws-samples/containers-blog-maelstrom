#!/usr/bin/env node

import 'source-map-support/register';
import * as cdk from 'aws-cdk-lib';
import * as blueprints from '@aws-quickstart/eks-blueprints';
import * as eks from "aws-cdk-lib/aws-eks";

const app = new cdk.App();

const account = process.env.GO_ACCOUNT_ID! || process.env.CDK_DEFAULT_ACCOUNT!;
const region = process.env.GO_AWS_REGION! || process.env.CDK_DEFAULT_REGION!;
const clusterName = process.env.GO_CLUSTER_NAME!;

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
    new blueprints.addons.AmpAddOn(),
];

const stack = blueprints.EksBlueprint.builder()
    .account(account)
    .region(region)
    .addOns(...addOns)
    .build(app, clusterName);


const cluster = stack.getClusterInfo().cluster;
const clusterSecretStore = new eks.KubernetesManifest(app, "ClusterSecretStore", {
    cluster: cluster,
    manifest: [
        {
            apiVersion: "external-secrets.io/v1beta1",
            kind: "ClusterSecretStore",
            metadata: {name: "default"},
            spec: {
                provider: {
                    aws: {
                        service: "SecretsManager",
                        region: region,
                        auth: {
                            jwt: {
                                serviceAccountRef: {
                                    name: "external-secrets-sa",
                                    namespace: "external-secrets",
                                },
                            },
                        },
                    },
                },
            },
        },
    ],
});

const keyfiles = new eks.KubernetesManifest(app, "ExternalSecret", {
    cluster: cluster,
    manifest: [
        {
            apiVersion: "external-secrets.io/v1beta1",
            kind: "ExternalSecret",
            metadata: {name: "external-grafana-admin-credentials"},
            spec: {
                secretStoreRef: {
                    name: "default",
                    kind: "ClusterSecretStore",
                },
                target: {
                    name: "grafana-admin-credentials",
                    creationPolicy: "Merge",
                },
                data: [
                    {
                        secretKey: "GF_SECURITY_ADMIN_APIKEY",
                        remoteRef: {
                            key: "GF_SECURITY_ADMIN_APIKEY"
                        },
                    },
                ],
            },
        },
    ],
});
