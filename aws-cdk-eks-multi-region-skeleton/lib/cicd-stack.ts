import * as cdk from 'aws-cdk-lib';
import codecommit = require('aws-cdk-lib/aws-codecommit');
import ecr = require('aws-cdk-lib/aws-ecr');
import { RemovalPolicy } from 'aws-cdk-lib'
import codepipeline = require('aws-cdk-lib/aws-codepipeline');
import pipelineAction = require('aws-cdk-lib/aws-codepipeline-actions');
import { codeToECRspec, deployToEKSspec } from '../utils/buildspecs';
import { Construct } from 'constructs';
import { CicdProps } from './cluster-stack';


export class CicdStack extends cdk.Stack {

    constructor(scope: Construct, id: string, props: CicdProps) {
        super(scope, id, props);

        const helloPyRepo = new codecommit.Repository(this, 'hello-py-for-demogo', {
            repositoryName: `hello-py-${cdk.Stack.of(this).region}`
        });
        
        new cdk.CfnOutput(this, `codecommit-uri`, {
            exportName: 'CodeCommitURL',
            value: helloPyRepo.repositoryCloneUrlHttp
        });
        const ecrForMainRegion = new ecr.Repository(this, `ecr-for-hello-py`,{
            removalPolicy: RemovalPolicy.DESTROY});

        const buildForECR = codeToECRspec(this, ecrForMainRegion.repositoryUri);
        ecrForMainRegion.grantPullPush(buildForECR.role!);
        
        const deployToMainCluster = deployToEKSspec(this, props.firstRegion, props.firstRegionCluster, ecrForMainRegion, props.firstRegionRole);
        const deployTo2ndCluster = deployToEKSspec(this, props.secondRegion, props.secondRegionCluster, ecrForMainRegion, props.secondRegionRole);


        const sourceOutput = new codepipeline.Artifact();

        new codepipeline.Pipeline(this, 'multi-region-eks-dep', {
                    stages: [ {
                            stageName: 'Source',
                            actions: [ new pipelineAction.CodeCommitSourceAction({
                                    actionName: 'CatchSourcefromCode',
                                    repository: helloPyRepo,
                                    output: sourceOutput,
                                })]
                        },{
                            stageName: 'Build',
                            actions: [ new pipelineAction.CodeBuildAction({
                                actionName: 'BuildAndPushtoECR',
                                input: sourceOutput,
                                project: buildForECR
                            })]
                        },
                        {
                            stageName: 'DeployToMainEKScluster',
                            actions: [ new pipelineAction.CodeBuildAction({
                                actionName: 'DeployToMainEKScluster',
                                input: sourceOutput,
                                project: deployToMainCluster
                            })]
                        },{
                            stageName: 'ApproveToDeployTo2ndRegion',
                            actions: [ new pipelineAction.ManualApprovalAction({
                                    actionName: 'ApproveToDeployTo2ndRegion'
                            })]
                        },
                        {
                            stageName: 'DeployTo2ndRegionCluster',
                            actions: [ new pipelineAction.CodeBuildAction({
                                actionName: 'DeployTo2ndRegionCluster',
                                input: sourceOutput,
                                project: deployTo2ndCluster
                            })]
                        }
                        
                    ]
                });

    }
}


