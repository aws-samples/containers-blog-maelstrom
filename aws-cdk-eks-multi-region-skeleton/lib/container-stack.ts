import * as cdk from 'aws-cdk-lib';
import { readYamlFromDir } from '../utils/read-file';
import { Construct } from 'constructs';
import { EksProps } from './cluster-stack'; 


export class ContainerStack extends cdk.Stack {
  constructor(scope: Construct, id: string, props: EksProps) {
    super(scope, id, props);
    
    const cluster = props.cluster;
    const commonFolder = './yaml-common/';
    const regionFolder = `./yaml-${cdk.Stack.of(this).region}/`;

    readYamlFromDir(commonFolder, cluster);
    readYamlFromDir(regionFolder, cluster);

    cluster.addHelmChart("Prometheus", {
      chart: "prometheus",
      release: "prometheus",
      version: "14.6.0",
      repository: "https://prometheus-community.github.io/helm-charts",
      values: {
        alertmanager: {
          persistentVolume: {
            storageClass: "gp2",
          },
        },
        server: {
          persistentVolume: {
            storageClass: "gp2",
          },
        },
      },
      namespace: "prometheus",
    });

  }

}


