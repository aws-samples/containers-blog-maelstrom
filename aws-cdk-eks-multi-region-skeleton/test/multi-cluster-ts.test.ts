import { expect as expectCDK, matchTemplate, MatchStyle } from 'aws-cdk-lib/assertions';
import * as cdk from 'aws-cdk-lib';
import MultiClusterTs = require('../lib/cluster-stack');

test('Empty Stack', () => {
    const app = new cdk.App();
    // WHEN
    const stack = new MultiClusterTs.ClusterStack(app, 'MyTestStack');
    // THEN
    expectCDK(stack).to(matchTemplate({
      "Resources": {}
    }, MatchStyle.EXACT))
});
