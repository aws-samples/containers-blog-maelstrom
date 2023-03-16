import 'source-map-support/register';
import * as blueprints from '@aws-quickstart/eks-blueprints';
import { Construct } from 'constructs';
import { dependable } from '@aws-quickstart/eks-blueprints/dist/utils';

const defaultProps: blueprints.HelmAddOnProps = {
    name: 'grafana-operator',
    chart: 'grafana-operator-v5.0.0-rc0',
    namespace: 'grafana-operator',
    repository: 'oci://ghcr.io/grafana-operator/helm-charts/grafana-operator',
    release: 'grafana-operator',
    version: 'v5.0.0-rc0',
    values: {}
};

export class GrafanaOperatorHelmAddon extends blueprints.HelmAddOn {

    constructor() {
        super({...defaultProps});
    }
    @dependable(blueprints.addons.ExternalsSecretsAddOn.name)
    deploy(clusterInfo: blueprints.ClusterInfo): void | Promise<Construct> {
        const chart = this.addHelmChart(clusterInfo, this.props, true);
        return Promise.resolve(chart);
    }
}