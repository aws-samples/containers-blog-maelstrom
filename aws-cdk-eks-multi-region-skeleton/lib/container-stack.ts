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

    cluster.addHelmChart(`flux`, {
      repository: 'https://charts.fluxcd.io',
      chart: 'flux',
      release: 'flux',
      values: {
        'git.url':'git@github.com\:org/repo'
      }
    });

  }

}


