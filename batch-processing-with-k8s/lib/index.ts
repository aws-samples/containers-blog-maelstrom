import * as path from 'path';
import * as cloudTrail from 'aws-cdk-lib/aws-cloudtrail';
import * as dynamodb from 'aws-cdk-lib/aws-dynamodb';
import * as ec2 from 'aws-cdk-lib/aws-ec2';
import { DockerImageAsset } from 'aws-cdk-lib/aws-ecr-assets';
import * as efs from 'aws-cdk-lib/aws-efs';
import * as eks from 'aws-cdk-lib/aws-eks';
import * as elasticcache from 'aws-cdk-lib/aws-elasticache';
import * as targets from 'aws-cdk-lib/aws-events-targets';
import * as iam from 'aws-cdk-lib/aws-iam';
import * as lambda from 'aws-cdk-lib/aws-lambda';
import * as s3 from 'aws-cdk-lib/aws-s3';
import * as stepFunctions from 'aws-cdk-lib/aws-stepfunctions';
import * as cdk from 'aws-cdk-lib';
import { Construct } from 'constructs';


// Customizable construct inputs
export interface KubernetesFileBatchInput {
  // VPC
  readonly vpc?: ec2.IVpc;

  // Min EKS worker nodes
  readonly minNodes?: number;

  // Max EKS worker nodes
  readonly maxNodes?: number;

  // Desired EKS worker nodes
  readonly desiredNodes?: number;

  // Input bucket that listens to file drop
  readonly inputBucket?: s3.Bucket;

  // Max number of lines per split file
  readonly maxSplitLines?: number;
}

// Main class
export class KubernetesFileBatchConstruct extends Construct {
  readonly vpc: ec2.IVpc;
  readonly minNodes?: number;
  readonly maxNodes?: number;
  readonly desiredNodes?: number;
  readonly inputBucket?: s3.Bucket;
  readonly maxSplitLines?: number;

  constructor(scope: Construct, id: string, props: KubernetesFileBatchInput) {
    super(scope, id);

    // Default values
    this.vpc = props.vpc ?? new ec2.Vpc(this, this.getId('k8s-vpc'), { natGateways: 1 });
    this.inputBucket = props.inputBucket ?? new s3.Bucket(this, 'inputBucket');
    this.minNodes = props.minNodes ?? 5;
    this.desiredNodes = props.desiredNodes ?? 5;
    this.maxNodes = props.maxNodes ?? 5;
    this.maxSplitLines = props.maxSplitLines ?? 30000;

    // Custom security group
    const securityGroup = new ec2.SecurityGroup(this, this.getId('security-group'), {
      vpc: this.vpc,
      allowAllOutbound: true,
    });

    // Allow inbound port 2049 (EFS), 6379 (ElasticCache), 22 (TCP)
    securityGroup.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(2049), 'Port 2049 for inbound traffic from IPv4');
    securityGroup.addIngressRule(ec2.Peer.anyIpv6(), ec2.Port.tcp(2049), 'Port 2049 for inbound traffic from IPv6');
    securityGroup.addIngressRule(ec2.Peer.anyIpv4(), ec2.Port.tcp(6379), 'Port 6379 for inbound traffic from IPv4');
    securityGroup.addIngressRule(ec2.Peer.anyIpv6(), ec2.Port.tcp(6379), 'Port 6379 for inbound traffic from IPv6');
    securityGroup.addIngressRule(ec2.Peer.anyIpv6(), ec2.Port.tcp(22), 'Port 22 for inbound traffic from IPv6');
    securityGroup.addIngressRule(ec2.Peer.anyIpv6(), ec2.Port.tcp(22), 'Port 22 for inbound traffic from IPv6');

    // Enable cloud trials and listen to write events on S3 bucket
    const trail = new cloudTrail.Trail(this, 'CloudTrail', {
      sendToCloudWatchLogs: true,
    });
    trail.addS3EventSelector(
      [
        {
          bucket: this.inputBucket,
        },
      ],
      {
        includeManagementEvents: false,
        readWriteType: cloudTrail.ReadWriteType.WRITE_ONLY,
      },
    );

    // EKS Cluster
    const cluster = new eks.Cluster(this, this.getId('ekscluster'), {
      vpc: this.vpc,
      version: eks.KubernetesVersion.V1_19,
      outputClusterName: true,
      outputConfigCommand: true,
      outputMastersRoleArn: true,
      securityGroup: securityGroup,
      defaultCapacity: 0,
    });

    // Add NodeGroup
    new eks.Nodegroup(this, this.getId('eksNodeGroup'), {
      cluster: cluster,
      amiType: eks.NodegroupAmiType.AL2_X86_64,
      instanceTypes: [new ec2.InstanceType('m5a.large')],
      minSize: this.minNodes,
      desiredSize: this.desiredNodes,
      maxSize: this.maxNodes,
      nodeRole: this.getRole('nodeRole', 'ec2.amazonaws.com',
        ['AmazonEKSWorkerNodePolicy', 'AmazonEC2ContainerRegistryReadOnly', 'AmazonEKS_CNI_Policy', 'AmazonElastiCacheFullAccess',
          'AmazonS3FullAccess', 'AmazonDynamoDBFullAccess', 'AmazonElasticFileSystemFullAccess', 'CloudWatchLogsFullAccess',
          'AmazonDynamoDBFullAccess', 'AmazonEC2FullAccess']),
    });

    // VPC endpoints for STS
    new ec2.InterfaceVpcEndpoint(this, this.getId('stsendpoint'), {
      service: ec2.InterfaceVpcEndpointAwsService.STS,
      vpc: this.vpc,
      open: true,
      securityGroups: [
        securityGroup,
      ],
    });

    // VPC endpoints for EFS
    new ec2.InterfaceVpcEndpoint(this, this.getId('efs'), {
      service: ec2.InterfaceVpcEndpointAwsService.ELASTIC_FILESYSTEM,
      vpc: this.vpc,
      open: true,
      securityGroups: [
        securityGroup,
      ],
    });

    // Creates Dynamodb table
    new dynamodb.Table(this, this.getId('orders'), {
      tableName: 'Order',
      partitionKey: {
        name: 'OrderId',
        type: dynamodb.AttributeType.STRING,
      },
      billingMode: dynamodb.BillingMode.PAY_PER_REQUEST,
    });

    // Create Elastic cache in cluster mode with Multi-AZ enabled
    const redisSubnetGroup = new elasticcache.CfnSubnetGroup(this, this.getId('RedisClusterPrivateSubnetGroup'), {
      subnetIds: this.vpc.selectSubnets({ subnetType: ec2.SubnetType.PRIVATE_WITH_NAT }).subnetIds,
      description: 'Subnet for elastic cache',
    });

    const redisReplication = new elasticcache.CfnReplicationGroup(this, this.getId('RedisReplicaGroup'), {
      engine: 'redis',
      cacheNodeType: 'cache.m5.xlarge',
      replicasPerNodeGroup: 1,
      numNodeGroups: 3,
      automaticFailoverEnabled: true,
      autoMinorVersionUpgrade: true,
      replicationGroupDescription: 'Redis cache replication',
      cacheSubnetGroupName: redisSubnetGroup.ref,
      securityGroupIds: [securityGroup.securityGroupId],
    });
    redisReplication.addDependsOn(redisSubnetGroup);
    redisReplication.addPropertyOverride('MultiAZEnabled', true);

    // Setup EFS artifacts
    const efsFileSystem = this.setupEfsArtifacts(cluster, securityGroup);
    const stepFunctionRole = this.getRole('stateRole', `states.${process.env.CDK_DEFAULT_REGION}.amazonaws.com`,
      ['AmazonEC2ContainerRegistryReadOnly', 'AmazonElastiCacheFullAccess', 'AmazonS3FullAccess',
        'AmazonDynamoDBFullAccess', 'AmazonElasticFileSystemFullAccess', 'CloudWatchLogsFullAccess',
        'AmazonDynamoDBFullAccess', 'AmazonEC2FullAccess', 'AWSLambda_FullAccess']);

    // Add step function role to `aws-auth` in kube-system so step function can execute k8s job in AWS EKS
    cluster.awsAuth.addRoleMapping(stepFunctionRole, {
      groups: ['system:masters'],
      username: stepFunctionRole.roleArn,
    });


    // Invoke multi-threaded step function on cloudWatch event
    const multiThreadedStepFunction = this.setMultiThreadMapFunction(cluster, stepFunctionRole, redisReplication, securityGroup);
    this.inputBucket.onCloudTrailWriteObject('WriteEvent', {
      target: new targets.SfnStateMachine(multiThreadedStepFunction),
    });
    new cdk.CfnOutput(this, 'Multithreadedstepfuction', {
      value: multiThreadedStepFunction.stateMachineName,
    });

    // Uncomment the below lines & comment lines from 177-179 to delete multithreaded and create single threaded step function
    // const singleThreadedStepFunction = this.setUpSingleThreadedStepFunction(cluster, stepFunctionRole);
    // this.inputBucket.onCloudTrailWriteObject('SingleThreadedWriteEvent', {
    //   target: new targets.SfnStateMachine(singleThreadedStepFunction),
    // });
    // new cdk.CfnOutput(this, 'Singlethreadedstepfuction', {
    //   value: singleThreadedStepFunction.stateMachineName,
    // });
    // CDK output
    new cdk.CfnOutput(this, this.getId('EFS-FileSystemId'), {
      exportName: 'Efs-File-SystemId',
      value: efsFileSystem.fileSystemId,
    });

    // Input bucket name
    new cdk.CfnOutput(this, 'InputBucketName', {
      value: this.inputBucket.bucketName,
    });
  }

  /**
     * Setup EFS artifacts, including installation of CSI driver and creating EFS file system
     * @param cluster EKS cluster
     * @param securityGroup AWS security group
   */
  setupEfsArtifacts(cluster: eks.Cluster, securityGroup: ec2.SecurityGroup): efs.FileSystem {
    const serviceAccount = {
      serviceAccount: new eks.ServiceAccount(this, this.getId('efs-csi-sa'), {
        name: 'csi-sa',
        cluster: cluster,
      }),
    };

    // Add service account to manage EFS
    serviceAccount.serviceAccount.addToPrincipalPolicy(new iam.PolicyStatement({
      effect: iam.Effect.ALLOW,
      actions: [
        'elasticfilesystem:*',
      ],
      resources: ['*'],
    }));

    // Setup helm chart with EFS CSI driver installed
    cluster.addHelmChart(this.getId('csiChart'), {
      chart: 'aws-efs-csi-driver',
      namespace: 'kube-system',
      repository: 'https://kubernetes-sigs.github.io/aws-efs-csi-driver/',
      values: {
        clusterName: cluster.clusterName,
        serviceAccount: {
          create: false,
          name: serviceAccount.serviceAccount.serviceAccountName,
        },
      },
    });

    // Create EFS file system with 40 mibps provisioned throughput
    const efsFileSystem = new efs.FileSystem(this, this.getId('FileSystem'), {
      vpc: this.vpc,
      encrypted: true,
      securityGroup: securityGroup,
      provisionedThroughputPerSecond: cdk.Size.mebibytes(40),
      throughputMode: efs.ThroughputMode.PROVISIONED,
      vpcSubnets: this.vpc.selectSubnets({ subnetType: ec2.SubnetType.PRIVATE_WITH_NAT }),
    });

    // Install k8s storageclass, persistantvolume and persistantclaim pointing the EFS
    const storageClass = cluster.addManifest(this.getId('storageClass'), {
      kind: 'StorageClass',
      apiVersion: 'storage.k8s.io/v1',
      metadata: {
        name: 'efs-sc',
      },
      provisioner: 'efs.csi.aws.com',
    });
    storageClass.node.addDependency(efsFileSystem);

    const persistentVolume = cluster.addManifest(this.getId('persistantVolume'), {
      apiVersion: 'v1',
      kind: 'PersistentVolume',
      metadata: {
        name: 'efs-pvc',
      },
      spec: {
        capacity: {
          storage: '5Gi',
        },
        volumeMode: 'Filesystem',
        accessModes: ['ReadWriteMany'],
        persistentVolumeReclaimPolicy: 'Retain',
        storageClassName: 'efs-sc',
        csi: {
          driver: 'efs.csi.aws.com',
          volumeHandle: `${efsFileSystem.fileSystemId}`,
        },
      },
    });
    persistentVolume.node.addDependency(storageClass);


    cluster.addManifest(this.getId('persistantVolumeClaim'), {
      apiVersion: 'v1',
      kind: 'PersistentVolumeClaim',
      metadata: {
        name: 'efs-storage-claim',
      },
      spec: {
        accessModes: ['ReadWriteMany'],
        storageClassName: 'efs-sc',
        resources: {
          requests: {
            storage: '5Gi',
          },
        },
      },
    });
    persistentVolume.node.addDependency(persistentVolume);

    return efsFileSystem;
  }

  /**
     * Setup step function with map that can run file processing in parallel using seperate k8s jobs
     * @param cluster EKS cluster
     * @param stepFunctionRole Step function IAM role
     * @param redis Elastic cache
     * @param securityGroup AWS security group
  */
  setMultiThreadMapFunction(cluster: eks.Cluster, stepFunctionRole: iam.Role,

    // Docker image for split-file k8s job
    redis: elasticcache.CfnReplicationGroup, securityGroup: ec2.SecurityGroup): stepFunctions.StateMachine {
    const splitFileAsset = new DockerImageAsset(this, this.getId('split-file-image'), {
      directory: path.join(__dirname, '../src/split-file'),
    });

    // This job internally leverages unix split command to break files into multiple lines and copy it to EFS directory
    const splitFileTask = new stepFunctions.CustomState(this, 'split-file-job', {
      stateJson: {
        Type: 'Task',
        Resource: 'arn:aws:states:::eks:runJob.sync',
        Parameters: {
          ClusterName: `${cluster.clusterName}`,
          CertificateAuthority: `${cluster.clusterCertificateAuthorityData}`,
          Endpoint: `${cluster.clusterEndpoint}`,
          LogOptions: {
            RetrieveLogs: false,
          },
          Job: {
            apiVersion: 'batch/v1',
            kind: 'Job',
            metadata: {
              generateName: 'split-file',
            },
            spec: {
              backoffLimit: 0,
              ttlSecondsAfterFinished: 100,
              template: {
                metadata: {
                  name: 'split-file',
                },
                spec: {
                  containers: [
                    {
                      name: 'split-file',
                      image: `${splitFileAsset.imageUri}`,
                      env: [
                        {
                          'name': 'S3_BUCKET_NAME',
                          'value.$': '$.detail.requestParameters.bucketName',
                        },
                        {
                          'name': 'S3_KEY',
                          'value.$': '$.detail.requestParameters.key',
                        },
                        {
                          'name': 'STATUS_KEY',
                          'value.$': '$.id',
                        },
                        {
                          name: 'EFS_DIRECTORY',
                          value: '/data',
                        },
                        {
                          name: 'MAX_LINES_PER_BATCH',
                          value: `${this.maxSplitLines}`,
                        },
                        {
                          name: 'REDIS_CACHE_ENDPOINT',
                          value: `${redis.attrConfigurationEndPointAddress}`,
                        },
                        {
                          name: 'REDIS_CACHE_PORT',
                          value: `${redis.attrConfigurationEndPointPort}`,
                        },
                        {
                          name: 'AWS_REGION',
                          value: 'us-east-1',
                        },
                      ],
                      volumeMounts: [
                        {
                          name: 'persistent-storage',
                          mountPath: '/data',
                        },
                      ],
                    },
                  ],
                  volumes: [
                    {
                      name: 'persistent-storage',
                      persistentVolumeClaim: {
                        claimName: 'efs-storage-claim',
                      },
                    },
                  ],
                  restartPolicy: 'Never',
                },
              },
            },
          },
        },
        OutputPath: '$.status.succeeded',
      },
    });

    // It takes care of reading the number of split files in cache and returning the array to map function (deployed as vpc only)
    const preMapLambda = new lambda.DockerImageFunction(this, this.getId('map-redis-get-lambda'), {
      code: lambda.DockerImageCode.fromImageAsset(path.resolve(__dirname, '../src/lambda-map-parallel')),
      memorySize: 512,
      timeout: cdk.Duration.seconds(30),
      role: this.getRole('lambda-role', 'lambda.amazonaws.com', ['CloudWatchLogsFullAccess', 'AmazonElastiCacheFullAccess', 'AmazonEC2FullAccess']),
      environment: {
        REDIS_CACHE_ENDPOINT: `${redis.attrConfigurationEndPointAddress}`,
        REDIS_CACHE_PORT: `${redis.attrConfigurationEndPointPort}`,
      },
      vpc: this.vpc,
      allowPublicSubnet: false,
      vpcSubnets: this.vpc.selectSubnets({ subnetType: ec2.SubnetType.PRIVATE_WITH_NAT }),
      securityGroups: [securityGroup],
    });
    const lambdaTask = new stepFunctions.CustomState(this, 'lambda-task-version', {
      stateJson: {
        Type: 'Task',
        Resource: 'arn:aws:states:::lambda:invoke',
        Parameters: {
          FunctionName: `${preMapLambda.functionArn}`,
          Payload: {
            'StatusKey.$': '$$.Execution.Input.id',
          },
        },
      },
    });

    // File processor docker image
    const mapProcessFileAsset = new DockerImageAsset(this, this.getId('map-process-asset'), {
      directory: path.join(__dirname, '../src/file-processor'),
    });

    // Task to process split file, save data in dynamodb and write output file back to EFS
    const mapState = new stepFunctions.CustomState(this, this.getId('file-map-version'), {
      stateJson: {
        Type: 'Task',
        Resource: 'arn:aws:states:::eks:runJob.sync',
        Parameters: {
          ClusterName: `${cluster.clusterName}`,
          CertificateAuthority: `${cluster.clusterCertificateAuthorityData}`,
          Endpoint: `${cluster.clusterEndpoint}`,
          LogOptions: {
            RetrieveLogs: true,
          },
          Job: {
            apiVersion: 'batch/v1',
            kind: 'Job',
            metadata: {
              generateName: 'map-version',
            },
            spec: {
              backoffLimit: 0,
              ttlSecondsAfterFinished: 100,
              template: {
                metadata: {
                  name: 'map-version',
                },
                spec: {
                  containers: [
                    {
                      name: 'map-version',
                      image: `${mapProcessFileAsset.imageUri}`,
                      env: [
                        {
                          'name': 'S3_BUCKET_NAME',
                          'value.$': '$$.Execution.Input.detail.requestParameters.bucketName',
                        },
                        {
                          'name': 'S3_KEY',
                          'value.$': '$$.Execution.Input.detail.requestParameters.key',
                        },
                        {
                          'name': 'INPUT_FILE',
                          'value.$': '$.MessageDetails',
                        },
                        {
                          'name': 'STATUS_KEY',
                          'value.$': '$.StatusKey.id',
                        },
                        {
                          name: 'EFS_DIRECTORY',
                          value: '/data',
                        },
                        {
                          name: 'REDIS_CACHE_ENDPOINT',
                          value: `${redis.attrConfigurationEndPointAddress}`,
                        },
                        {
                          name: 'REDIS_CACHE_PORT',
                          value: `${redis.attrConfigurationEndPointPort}`,
                        },
                        {
                          name: 'AWS_REGION',
                          value: 'us-east-1',
                        },
                      ],
                      volumeMounts: [
                        {
                          name: 'persistent-storage',
                          mountPath: '/data',
                        },
                      ],
                    },
                  ],
                  volumes: [
                    {
                      name: 'persistent-storage',
                      persistentVolumeClaim: {
                        claimName: 'efs-storage-claim',
                      },
                    },
                  ],
                  restartPolicy: 'Never',
                },
              },
            },
          },
        },
        OutputPath: '$.status.succeeded',
      },
    });

    /*
        Map task in step function to take in redis cache (containing input file path in EFS) and distributing it as
        separate k8s jobs
    */
    const mapOrchestrator = new stepFunctions.Map(this, this.getId('map-orchestrator'), {
      inputPath: '$.Payload',
      parameters: {
        'MessageNumber.$': '$$.Map.Item.Index',
        'MessageDetails.$': '$$.Map.Item.Value',
        'StatusKey.$': '$$.Execution.Input',
      },
      maxConcurrency: 0,
    }).iterator(mapState);

    // Step function definition
    return new stepFunctions.StateMachine(this, this.getId('multi-threaded'), {
      definition: splitFileTask.next(lambdaTask.next(mapOrchestrator)),
      role: stepFunctionRole,
      tracingEnabled: true,
    });
  }

  /**
     * A step function which has use single k8s job to process the input file, save data to dynamodb and write the output
     * back to S3
     * @param cluster EKS cluster
     * @param stepFunctionRole Step function IAM role
  */
  setUpSingleThreadedStepFunction(cluster: eks.Cluster, stepFunctionRole: iam.Role) {

    // file processor docker image
    const asset = new DockerImageAsset(this, this.getId('single-threaded-image'), {
      directory: path.join(__dirname, '../src/single-thread-processor'),
    });

    // Step running the file processor as k8s job
    const customState = new stepFunctions.CustomState(this, 'single-threaded-version', {
      stateJson: {
        Type: 'Task',
        Resource: 'arn:aws:states:::eks:runJob.sync',
        Parameters: {
          ClusterName: `${cluster.clusterName}`,
          CertificateAuthority: `${cluster.clusterCertificateAuthorityData}`,
          Endpoint: `${cluster.clusterEndpoint}`,
          LogOptions: {
            RetrieveLogs: false,
          },
          Job: {
            apiVersion: 'batch/v1',
            kind: 'Job',
            metadata: {
              generateName: 'single-threaded',
            },
            spec: {
              backoffLimit: 0,
              ttlSecondsAfterFinished: 100,
              template: {
                metadata: {
                  name: 'single-threaded',
                },
                spec: {
                  containers: [
                    {
                      name: 'single-threaded-container',
                      image: `${asset.imageUri}`,
                      env: [
                        {
                          'name': 'S3_BUCKET_NAME',
                          'value.$': '$.detail.requestParameters.bucketName',
                        },
                        {
                          'name': 'S3_KEY',
                          'value.$': '$.detail.requestParameters.key',
                        },
                        {
                          'name': 'STATUS_KEY',
                          'value.$': '$.id',
                        },
                        {
                          name: 'EFS_DIRECTORY',
                          value: '/data',
                        },
                        {
                          name: 'AWS_REGION',
                          value: 'us-east-1',
                        },
                      ],
                      volumeMounts: [
                        {
                          name: 'persistent-storage',
                          mountPath: '/data',
                        },
                      ],
                    },
                  ],
                  volumes: [
                    {
                      name: 'persistent-storage',
                      persistentVolumeClaim: {
                        claimName: 'efs-storage-claim',
                      },
                    },
                  ],
                  restartPolicy: 'Never',
                },
              },
            },
          },
        },
        OutputPath: '$.status.succeeded',
        End: true,
      },
    });

    // return newly created step function
    return new stepFunctions.StateMachine(this, this.getId('single-threaded'), {
      definition: customState,
      role: stepFunctionRole,
    });
  }

  /**
     * Creates new IAM role
     * @param id referenceId
     * @param principal trust ship principal
     * @param roles AWS managed policy associated with the roles
  */
  getRole(id: string, principal: string, roles : string[]): iam.Role {
    const nodeRole = new iam.Role(this, this.getId(id), {
      assumedBy: new iam.ServicePrincipal(principal),
    });

    roles.forEach(function(x) {
      nodeRole.addManagedPolicy(iam.ManagedPolicy.fromAwsManagedPolicyName(x));
    });

    return nodeRole;
  }

  /**
     * Generates reference prefixed with a constant identifier
     * @param id suffix
   */
  getId(id: string) {
    return 'file-batch' + id;
  }
}
