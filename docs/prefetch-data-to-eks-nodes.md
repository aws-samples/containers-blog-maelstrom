# Event Driven process to prefetch data to EKS Nodes using SSM Automation


### Introduction

Benefits of Event-Driven Data Prefetching Event-driven data prefetching provides several benefits, including:

Improved performance: By fetching data in anticipation of future requests, you can reduce the latency and improve the overall user experience.

Reduced server load: By fetching data ahead of time, you can reduce the load on your servers, allowing them to handle more requests.

Increased reliability: By automating the process of fetching data, you can reduce the risk of errors and improve the reliability of your system.

In this blog, we will demonstrate the usage of AWS Systems Manager SSM Automation and State Manager to prefetch container images to your existing and newer worker nodes of your Amazon EKS Cluster.

### Solution Overview

Below is the overall architecture for setting up **Event Driven process to prefetch data to EKS Nodes using SSM Automation**
[Image: Image.jpg]The process for implementing this solution is as follows:

* The first step is to identify the image repository to fetch the container image. The container image repository could be Amazon Elastic Container Registry (Amazon ECR), DockerHub or others. For this demonstration we are using Amazon ECR as the image source.
* Next, when a container image gets pushed to Amazon ECR, an event based rule is triggered  by Amazon EventBridge to trigger an AWS SSM automation to prefetch container images from Amazon ECR to your existing Amazon EKS worker nodes.
* Whenever a newer worker node gets added to your Amazon EKS cluster, based on the tags on the worker node, Systems Manager State Manager Association on tags acts on to prefetch container images to newly created worker nodes.

### Solution Walkthrough

#### Prerequisites

To run this solution, you must have the following prerequisites:

* [AWS CLI version 2.10 or higher](https://docs.aws.amazon.com/cli/latest/userguide/install-cliv2.html) to interact with AWS services
* [eksctl](https://docs.aws.amazon.com/eks/latest/userguide/eksctl.html) for creating and managing your Amazon EKS cluster
* [kubectl](https://docs.aws.amazon.com/eks/latest/userguide/install-kubectl.html) for running kubectl commands on your Amazon EKS cluster
* [envsubst](https://yum-info.contradodigital.com/view-package/base/gettext/) for environment variables substitution (envsubst is included in gettext package)
* [jq](https://stedolan.github.io/jq/download/) for command-line JSON processing


The source code for this blog is available in AWS-Samples on [GitHub](https://github.com/aws-samples/containers-blog-maelstrom/tree/main/prefetch-data-to-EKSnodes).

Let’s start by setting a few environment variables:

```
export EDP_AWS_REGION=us-east-1
export EDP_AWS_ACCOUNT=$(aws sts get-caller-identity --query 'Account' --output text)
export EDP_NAME=prefetching-data-automation

```

Next, lets create Amazon Elastic Container Registry repository for your AWS account :

```
aws ecr create-repository \
    --cli-input-json file://EDP-Repo.json  \
    --repository-name ${EDP_NAME}
```

Next, lets create an Amazon EKS Cluster using the below commands. Using envsubst utility we will be replacing the variables in the Yaml Config file and the eksctl CLI tool will deploy the cluster using the EDP-Cluster-Config`.yaml` file:

```
envsubst < EDP-Cluster-Config.yaml | eksctl create cluster -f -
```

Next, Build a large docker image size of approximately 1 GB to test this solution by running shell script EDP-Build-Docker-Image.sh:

```
./EDP-Build-Docker-Image.sh
```

we will create `prefetching-data-automation-role` with trust policy  EDP-Events-Trust-Policy`.json `which will be assumed by Amazon EventBridge service:

```
aws iam create-role \
    --role-name $EDP_NAME-role \
    --assume-role-policy-document file://EDP-Events-Trust-Policy.json

```

we will run the below command to replace variables in EDP-Events-Policy.json policy file by using envsubst utility and attach the policy to the above created ``prefetching-data-automation-role` :

```
aws iam put-role-policy \
    --role-name ${EDP_NAME}-role \
    --policy-name ${EDP_NAME}-policy \
    --policy-document "$(envsubst < EDP-Events-Policy.json)"
```

Next, lets create Amazon EventBridge Rule to trigger SSM Run Command on successful ECR Image push, using envsubst we will be replacing the variables in the EDP-Events-Rule.json:

```
envsubst < EDP-Events-Rule.json > EDP-Events-Rule-updated.json && aws events put-rule --cli-input-json file://EDP-Events-Rule-updated.json && rm EDP-Events-Rule-updated.json
```

Next, lets Attach the Target as AWS Systems Manager Run Command to AWS EventBridge Rule created above, using envsubst we will be replacing the variables in the EDP-Events-Target.json :

```
envsubst '$EDP_AWS_REGION $EDP_AWS_ACCOUNT $EDP_NAME' < EDP-Events-Target.json > EDP-Events-Target-updated.json && aws events put-targets --rule $EDP_NAME --cli-input-json file://EDP-Events-Target-updated.json && rm EDP-Events-Target-updated.json 
```

Next, lets create AWS Systems Manager State Manager Association for new worker nodes to prefetch container images, using envsubst we will be replacing the variables in the EDP-StateManager-Association.json:

```
envsubst '$EDP_AWS_REGION $EDP_AWS_ACCOUNT $EDP_NAME' < EDP-StateManager-Association.json > EDP-StateManager-Association-updated.json && aws ssm create-association --cli-input-json file://EDP-StateManager-Association-updated.json && rm EDP-StateManager-Association-updated.json
```

Note: Status might show failed for the AWS SSM State Manager association as there is no image present in ECR yet.

#### Validation

Now the setup is complete, let’s run some validations on the setup for Event Driven process to prefetch data to EKS Nodes,

***First test** is to verify if the container images are getting fetched to existing worker nodes automatically upon a container image push.* 

Lets run the following command to get authenticated with ECR repository and push the created container image to Amazon ECR :

```
aws ecr get-login-password \
    --region $EDP_AWS_REGION | docker login \
    --username AWS \
    --password-stdin $EDP_AWS_ACCOUNT.dkr.ecr.$EDP_AWS_REGION.amazonaws.com

```

```
docker push $EDP_AWS_ACCOUNT.dkr.ecr.$EDP_AWS_REGION.amazonaws.com/$EDP_NAME
```

Now lets check if the event rule we created on the Amazon EventBridge has been triggered. In your Amazon EventBridge console, Navigate to **TriggeredRules** under **Monitoring** tab. If there are no **FailedInvocations** datapoints, then EventBridge has delivered the event to the target successfully which in this case is AWS Systems Manager Run Command (Note: It might take 3 to 5 mins for the data points to be published in the Monitoring graphs)
[Image: Image.jpg]Next lets verify if AWS Systems Manager Run Command is triggered by Amazon EventBridge. Run the below command to see the invocations. Look for `DocumentName` which should be `AWS-RunShellScript`, `RequestedDateTime` to identify corresponding run, and then status to make sure if the Run Command executed Successfully or not.

```
aws ssm list-command-invocations \
    --details \
    --filter "[{\"key\": \"DocumentName\", \"value\": \"arn:aws:ssm:us-east-1::document/AWS-RunShellScript\"}]"

```

```
Output:

{
    "CommandInvocations": [
        {
            "CommandId": "eeb9d869-421d-488f-b1ba-ce93a69db2b0",
            "InstanceId": "i-0e1a4977c389*****",
            "InstanceName": "ip-192-168-29-214.ec2.internal",
            "Comment": "",
            "DocumentName": "arn:aws:ssm:us-east-1::document/AWS-RunShellScript",
            "DocumentVersion": "$DEFAULT",
            "RequestedDateTime": "2023-02-17T17:35:48.520000-06:00",
            "Status": "Success",
            "StatusDetails": "Success",
            .......
            .......
```

Next, lets verify if the Image has been copied in to worker node of your Amazon EKS Cluster using the below command:

```
aws ec2 describe-instances \
    --filters "Name=tag:eks:cluster-name,Values=$EDP_NAME" "Name=tag:eks:nodegroup-name,Values=nodegroup" \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text | xargs -I {} aws ssm start-session \
    --target {} \
    --document-name AWS-StartInteractiveCommand \
    --parameters "command=echo \$(curl -s http://169.254.169.254/latest/meta-data/instance-id) && sudo docker images" \
    --region $EDP_AWS_REGION
```

```
Output:

Starting session with SessionId: nbbat-0cf87cdf534*****
........
REPOSITORY                                                                 TAG                  IMAGE ID       CREATED          SIZE
0266528*****.dkr.ecr.us-east-1.amazonaws.com/prefetching-data-automation   latest               d50f7ccece64   50 minutes ago   1.23GB
.......

```

***Second Test** is to validate the container image getting copied to new worker node for any newly added Amazon EKS worker node*

Lets create new worker node as part of EKS Cluster using below command :

```
eksctl scale nodegroup \
    --cluster $EDP_NAME \
    --name nodegroup \
    --nodes 2 \
    --nodes-min 1 \
    --nodes-max 3
```

Next, lets verify if the AWS System Manager State Manager Association has been triggered and association execution is successful. Note: Please wait for for few minutes for new worker node to come up and run below command

```
aws ssm list-associations \
--association-filter-list "key=AssociationName,value=$EDP_NAME"
```

```
Output:

{
    "Associations": [
        {
            "Name": "AWS-RunShellScript",
            "AssociationId": "d9c82d84-0ceb-4f0f-a8d8-35cd67d1a66e",
......
                "AssociationStatusAggregatedCount": {
                    "Failed": 1,
                    "Success": 1
                }
            },
            "AssociationName": "prefetching-data-automation"
        }
    ]
}
```

Next, lets verify if the Image has been copied in to worker node of your Amazon EKS Cluster using the below command:

```
aws ec2 describe-instances \
    --filters "Name=tag:eks:cluster-name,Values=$EDP_NAME" "Name=tag:eks:nodegroup-name,Values=nodegroup" \
    --query "Reservations[*].Instances[*].InstanceId" \
    --output text | xargs -I {} aws ssm start-session \
    --target {} \
    --document-name AWS-StartInteractiveCommand \
    --parameters "command=echo \$(curl -s http://169.254.169.254/latest/meta-data/instance-id) && sudo docker images" \
    --region $EDP_AWS_REGION
```

```
Output:

Starting session with SessionId: nbbat-0cf87cdf5347*****
........
REPOSITORY                                                                 TAG                  IMAGE ID       CREATED          SIZE
0266528*****.dkr.ecr.us-east-1.amazonaws.com/prefetching-data-automation   latest               d50f7ccece64   50 minutes ago   1.23GB
.......
```


***Final Test** is identify the time difference for a Kubernetes pod to get to running with a Container Image pulled from Amazon ECR vs Image pulled locally

_Final Test A_*

Delete the locally cached/copied image from one of the worker nodes using the following commands

```
# Grab the instance ID
InstanceID=$(kubectl get nodes -o jsonpath='{.items[*].spec.providerID}' | awk -F/ '{print $NF}')
```

```
# SSH to the instance
aws ssm start-session \
    --target $InstanceID \
    --region $EDP_AWS_REGION
```

```
# List the locally cached image that you pushed in one of the above step
sudo su
docker images
```

```
# Delete the locally cached images
docker rmi <docker image id identified above>
```

Exit out of the SSM session

Next, lets pull the latest container image and create a Kubernetes Pod :

```
sh EDP-Pod.sh
```

```
kubectl apply -f EDP-Pod.yaml 
```

Now lets run below command to check how long it took for pod to get in to running state

```
kubectl describe pod $EDP_NAME
```

Output:

```
nbbathul@88665a1f8bb5 EDP_Working % kubectl describe pod prefetching-data-automation
Name:         prefetching-data-automation
Namespace:    default
Priority:     0
Node:         ip-192-168-19-136.ec2.internal/192.168.19.136
Start Time:   Thu, 09 Mar 2023 23:03:52 -0600
Labels:       <none>
Annotations:  kubernetes.io/psp: eks.privileged
Status:       Running
IP:           192.168.23.89
IPs:
  IP:  192.168.23.89
Containers:
  prefetching-data-automation:
    Container ID:  containerd://29579b61aaca8597bade857458e95b669ab7fca142c1e8f733cfec07d15d9d4d
    Image:         022435809194.dkr.ecr.us-east-1.amazonaws.com/prefetching-data-automation:latest
    Image ID:      022435809194.dkr.ecr.us-east-1.amazonaws.com/prefetching-data-automation@sha256:d7a93473bd682ed53acbaba18405532e6c1026c35b7d04ffc96ad89d2221736c
    Port:          <none>
    Host Port:     <none>
    Command:
      sleep
      3600
    State:          Running
      Started:      Thu, 09 Mar 2023 23:04:52 -0600
    Ready:          True
    Restart Count:  0
    Environment:    <none>
```


Next, lets also validate time take by pod to get in to running state by running below commands

```
chmod +x EDP-Get-Pod-Boot-Time.sh
```

Note: Comment line 12 and uncomment line 13 if you are running on linux kernel

```
for pod in $(kubectl get --no-headers=true pods -o name | awk -F "/" '{print $2}'); do ./EDP-Get-Pod-Boot-Time.sh $pod ; done >> EDP-Pod-Up-Time-With-Image-From-ECR.txt
```

```
cat EDP-Pod-Up-Time-With-Image-From-ECR.txt
```

Output :

```
It took 60 seconds for test to boot up
```


*_Final Test B_*

Next, delete the Kubernetes Pod, create another pod by using sample pod definition file created in above and calculated the time it took to get to running state, since the image is cached locally this time it shouldn’t take long to start the pod :


```
kubectl delete pod $EDP_NAME
kubectl apply -f EDP-Pod.yaml 
```

Now lets run below command to check how long it took for pod to get in to running state

```
kubectl describe pod $EDP_NAME
```

Output:

```
nbbathul@88665a1f8bb5 EDP_Working % kubectl describe pod prefetching-data-automation                                                                                                                        
Name:         prefetching-data-automation
Namespace:    default
Priority:     0
Node:         ip-192-168-19-136.ec2.internal/192.168.19.136
Start Time:   Thu, 09 Mar 2023 23:20:05 -0600
Labels:       <none>
Annotations:  kubernetes.io/psp: eks.privileged
Status:       Running
IP:           192.168.10.39
IPs:
  IP:  192.168.10.39
Containers:
  prefetching-data-automation:
    Container ID:  containerd://fc06a2c5f5ee7734b2a9c4fd893acd1aca7c314ba035b6a01fa9954ae48a69fb
    Image:         022435809194.dkr.ecr.us-east-1.amazonaws.com/prefetching-data-automation:latest
    Image ID:      022435809194.dkr.ecr.us-east-1.amazonaws.com/prefetching-data-automation@sha256:d7a93473bd682ed53acbaba18405532e6c1026c35b7d04ffc96ad89d2221736c
    Port:          <none>
    Host Port:     <none>
    Command:
      sleep
      3600
    State:          Running
      Started:      Thu, 09 Mar 2023 23:20:06 -0600
    Ready:          True
    Restart Count:  0
    Environment:    <none>
```


Next, lets also validate time take by pod to get in to running state by running below commands

```
for pod in $(kubectl get --no-headers=true pods -o name | awk -F "/" '{print $2}'); do ./EDP-Get-Pod-Boot-Time.sh $pod ; done >> EDP-Pod-Up-Time-With-Image-From-Workernode.txt
```

```
cat EDP-Pod-Up-Time-With-Image-From-Workernode.txt
```

Output:

```
It took 1 second for test to boot up
```


Below table shows  time it took for Pod that has been created with locally cached image is drastically less when compared to Pod that has been created with image that got pulled from ECR repository.

|Entity	|Final Test A (Created Pod by pulling image from ECR repo)	|Final Test B (Created Pod by pulling locally cached Image)	|
|---	|---	|---	|
|Pod Start Time	|23:03:52 -0600	|23:20:05 -0600	|
|Pod Running Time	|23:04:52 -0600	|23:20:06 -0600	|
|Total Time Taken	|60 Seconds	|1 Second	|

## Cleanup

```
chmod +x EDP-Cleanup.sh
```

```
./EDP-Cleanup.sh
```

## Conclusion

In this blog, we demonstrated the usage of AWS Systems Manager SSM Automation and State Manager to prefetch container images to your existing and newer worker nodes of your Amazon EKS Cluster. We clearly demonstrated a clear differentiation in run times when your container images are prefetched to worker nodes. This solution will be very effective for run machine learning, analytics and other complex containerized workloads having large container images which otherwise needs lot of time to cache locally. 
For more information, see the following references:


* * *














# Appendix (do not publish)

    * 




## **References**


https://gitlab.aws.dev/aws-tfc-containers/containers-content-tracker/-/issues/741

https://stackoverflow.com/questions/72298729/how-to-pull-image-from-a-private-repository-using-containerd (CTR Command)


```
aws ecr get-login-password \                                                                                         ─╯
    --region us-east-1 | helm registry login \
    --username AWS \
    --password-stdin 709825985650.dkr.ecr.us-east-1.amazonaws.com
```



##########################################

**Complete Solution Below**

[Amazon Elastic Container Registry (Amazon ECR)](https://aws.amazon.com/ecr/) is an AWS managed container image registry service that is secure, scalable, and reliable. Amazon ECR supports private repositories with resource-based permissions using AWS IAM. This is so that specified users or Amazon EC2 instances can access your container repositories and images. You can use your preferred CLI to push, pull, and manage Docker images, Open Container Initiative (OCI) images, and OCI compatible artifacts.

[Amazon Elastic Kubernetes Service (EKS)](https://aws.amazon.com/eks/) is a managed Kubernetes service that makes it easy to deploy, manage, and scale containerized applications using Kubernetes on AWS. With EKS, you can easily run and manage containers in a highly available and scalable fashion.

[AWS Systems Manager (SSM)](https://www.amazonaws.cn/en/systems-manager/) is the operations hub for your AWS applications and resources and a secure end-to-end management solution for hybrid cloud environments that enables secure operations at scale.

[AWS Systems Manager Run Command](https://docs.aws.amazon.com/systems-manager/latest/userguide/run-command.html) is a capability of AWS Systems Manager that lets you remotely and securely manage the configuration of your managed nodes. A *managed node* is any Amazon Elastic Compute Cloud (Amazon EC2) instance, edge device, or on-premises server or virtual machine (VM) in your hybrid environment that has been configured for Systems Manager. Run Command allows you to automate common administrative tasks and perform one-time configuration changes at scale.

[AWS Systems Manager State Manager](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-state.html) a capability of AWS Systems Manager, is a secure and scalable configuration management service that automates the process of keeping your managed nodes and other AWS resources in a state that you define.

[AWS Systems Manager Parameter Store](https://docs.aws.amazon.com/systems-manager/latest/userguide/systems-manager-parameter-store.html) a capability of AWS Systems Manager, provides secure, hierarchical storage for configuration data management and secrets management. You can store data such as passwords, database strings, Amazon Machine Image (AMI) IDs, and license codes as parameter values. You can store values as plain text or encrypted data. You can reference Systems Manager parameters in your scripts, commands, SSM documents, and configuration and automation workflows by using the unique name that you specified when you created the parameter.

Event-driven processes are a popular way to manage and execute workloads in a dynamic and efficient manner. One of the key components in such processes is the efficient and timely retrieval of data. In this blog, we'll look at how you can prefetch data to your Amazon EKS nodes using AWS Systems Manager (SSM) Automation.

First, let's understand why prefetching data is important. When you run a workload in a cluster, it's essential that the nodes have access to all the required data, so that the process can run smoothly and efficiently. However, if the data is stored in a remote location, the retrieval process can take a significant amount of time, affecting the overall performance of the cluster.

One solution to this problem is to prefetch the data to the nodes before the process starts, so that the nodes have immediate access to the data when it is needed. This is where AWS Systems Manager capabilities comes in.


## Architecture


The figure below illustrates the overall architecture of automating **Event Driven process to prefetch data to EKS Nodes using SSM


**
[Image: Image.jpg]

## Solution Overview


The process of implementing **Event Driven process to prefetch data to EKS Nodes using SSM Automation** involves the following steps:


* Identify the data sources The first step is to identify the data sources that you want to fetch data from. This could be a ECR Repo, a file system, or Git Hub Repo (In our case it is ECR Repo)
* To prefetch data to your EKS nodes using SSM Automation, you need to create Amazon EventBridge Rule(Event Based) that gets invoked by source (in our case it is ECR image push success). 
* Attach a target to Amazon EventBridge Rule which is Amazon Systems Manager Run Command by choosing [AWS-RunShellScript](https://us-east-1.console.aws.amazon.com/systems-manager/documents/AWS-RunShellScript/content?region=us-east-1) document and by passing shell command to it which will prefetch the image/data to the existing nodes. 
* Create a AWS Systems Manager State Manager Association on tags for worker Node to prefetch the image/data to the newly created worker nodes.



Verify ECR repository creation

```
aws ecr describe-repositories --repository-names $NAME
```

Output:

```
{
    "repository": {
        "repositoryArn": "arn:aws:ecr:us-east-1:026652815482:repository/prefetching-data-automation",
        "registryId": "026652815482",
        "repositoryName": "prefetching-data-automation",
        "repositoryUri": "026652815482.dkr.ecr.us-east-1.amazonaws.com/prefetching-data-automation",
        "createdAt": "2023-02-17T16:12:52-06:00",
        "imageTagMutability": "MUTABLE",
        "imageScanningConfiguration": {
            "scanOnPush": false
        },
        "encryptionConfiguration": {
            "encryptionType": "AES256"
        }
    }
}
```

@Verify Cluster creation

```
aws eks describe-cluster --name $NAME
```

Output:

```
{
    "cluster": {
        "name": "prefetching-data-automation",
        "arn": "arn:aws:eks:us-east-1:026652815482:cluster/prefetching-data-automation",
        "createdAt": "2023-02-17T16:17:22.289000-06:00",
        "version": "1.21",
        "endpoint": "https://03F101B6E05DF10B85CCA9DBABEC077A.gr7.us-east-1.eks.amazonaws.com",
        "roleArn": "arn:aws:iam::026652815482:role/eksctl-prefetching-data-automation-clu-ServiceRole-14I8Y9U5I8XD0",
        "resourcesVpcConfig": {
            "subnetIds": [
                "subnet-01fa7dee34b3fea8b",
                "subnet-02361ca3d60baa13f",
                "subnet-0b9a9b1997921702a",
                "subnet-0a68cb84dc158afb6"
            ],
            "securityGroupIds": [
                "sg-08677fe9863a9e235"
            ],
            "clusterSecurityGroupId": "sg-02ed51984700e014b",
            "vpcId": "vpc-081f43f476b2f9198",
            "endpointPublicAccess": true,
            "endpointPrivateAccess": false,
            "publicAccessCidrs": [
                "0.0.0.0/0"
            ]
        },
        "kubernetesNetworkConfig": {
            "serviceIpv4Cidr": "10.100.0.0/16"
        }
```

Verify Docker Image has been created

```
docker images
```

Output:

```
REPOSITORY                                                                 TAG       IMAGE ID       CREATED              SIZE
026652815482.dkr.ecr.us-east-1.amazonaws.com/prefetching-data-automation   latest    d50f7ccece64   About a minute ago   1.23GB
prefetching-data-automation                                                latest    d50f7ccece64   About a minute ago   1.23GB
```

Verify role creation

```
aws iam get-role --role-name $NAME-role
```

Output:

```
{
    "Role": {
        "Path": "/",
        "RoleName": "prefetching-data-automation-role",
        "RoleId": "AROAQMNFBWB5PR3QV3JJ5",
        "Arn": "arn:aws:iam::026652815482:role/prefetching-data-automation-role",
        "CreateDate": "2023-02-17T23:06:27+00:00",
        "AssumeRolePolicyDocument": {
            "Version": "2012-10-17",
            "Statement": [
                {
                    "Sid": "",
                    "Effect": "Allow",
                    "Principal": {
                        "Service": "events.amazonaws.com"
                    },
                    "Action": "sts:AssumeRole"
                }
            ]
        },
        "MaxSessionDuration": 3600,
        "RoleLastUsed": {}
    }
}
```

Verify Amazon EventBridge Rule Creation

```
aws events list-rules --name-prefix $NAME
```

Output:

```
{
    "Rules": [
        {
            "Name": "prefetching-data-automation",
            "Arn": "arn:aws:events:us-east-1:026652815482:rule/prefetching-data-automation",
            "EventPattern": "{\"source\": [\"aws.ecr\"],\"detail-type\": [\"ECR Image Action\"],\"detail\": {\"action-type\": [\"PUSH\"],\"result\": [\"SUCCESS\"],\"repository-name\": [\"prefetching-data-automation\"]}}",
            "State": "ENABLED",
            "Description": "Rule to trigger SSM Run Command on ECR Image PUSH Action Success",
            "EventBusName": "default"
        }
    ]
}
```

Verify target attachment

```
aws events list-targets-by-rule --rule $NAME
```

Output:

```
{
    "Targets": [
        {
            "Id": "Id4000985d-1b4b-4e14-8a45-b04103f9871b",
            "Arn": "arn:aws:ssm:us-east-1::document/AWS-RunShellScript",
            "RoleArn": "arn:aws:iam::026652815482:role/prefetching-data-automation-role",
            "Input": "{\"commands\":[\"sudo su\",\"aws ecr get-login-password --region us-east-1 | docker login --username AWS --password-stdin 026652815482.dkr.ecr.us-east-1.amazonaws.com\",\"tag=$(aws ecr describe-images --repository-name prefetching-data-automation --query 'sort_by(imageDetails,& imagePushedAt)[-1].imageTags[0]' --output text)\",\"echo $tag\",\"docker pull 026652815482.dkr.ecr.us-east-1.amazonaws.com/prefetching-data-automation:$tag\"]}",
            "RunCommandParameters": {
                "RunCommandTargets": [
                    {
                        "Key": "tag:Name",
                        "Values": [
                            "prefetching-data-automation-nodegroup-Node"
                        ]
                    }
                ]
            }
        }
    ]
}
```

Verify Association Creation

```
aws ssm list-associations --association-filter-list "key=AssociationName,value=$NAME" 
```

Output:

```
{
    "Associations": [
        {
            "Name": "AWS-RunShellScript",
            "AssociationId": "d9c82d84-0ceb-4f0f-a8d8-35cd67d1a66e",
            "AssociationVersion": "1",
            "Targets": [
                {
                    "Key": "tag:Name",
                    "Values": [
                        "prefetching-data-automation-nodegroup-Node"
                    ]
                }
            ],
            "LastExecutionDate": "2023-02-17T17:14:12.966000-06:00",
            "Overview": {
                "Status": "Failed",
                "DetailedStatus": "Failed",
                "AssociationStatusAggregatedCount": {
                    "Failed": 1
                }
            },
            "AssociationName": "prefetching-data-automation"
        }
    ]
}
```

* Verify that the image is present in Amazon ECR repository.

```
aws ecr list-images --repository-name $NAME
```

Output:

```
{
    "imageIds": [
        {
            "imageDigest": "sha256:a449c25766fa8f1e6257b16b5ef07faf1448d1110e86b025ea5e42cf0c94cf31",
            "imageTag": "latest"
        }
    ]
}
```

@TriggeredRules: The number of rules that have run and matched with any event. You won’t see this metric in CloudWatch until a rule is triggered

Invocations: The number of times a target is invoked by a rule in response to an event

Failed Invocations: The number of invocations that failed permanently.


Output: 

```
Starting session with SessionId: nbbathul-08b30b957424cba44
seelog internal error: invalid argument
seelog internal error: invalid argument
seelog internal error: invalid argument
REPOSITORY                                                                 TAG                  IMAGE ID       CREATED             SIZE
026652815482.dkr.ecr.us-east-1.amazonaws.com/prefetching-data-automation   latest               d50f7ccece64   About an hour ago   1.23GB
602401143452.dkr.ecr.us-east-1.amazonaws.com/amazon-k8s-cni-init           v1.10.1-eksbuild.1   b65b61ecb390   15 months ago       276MB
602401143452.dkr.ecr.us-east-1.amazonaws.com/amazon-k8s-cni                v1.10.1-eksbuild.1   407b33483c87   15 months ago       302MB
602401143452.dkr.ecr.us-east-1.amazonaws.com/eks/kube-proxy                v1.21.2-eksbuild.2   5fb0f8c056e6   19 months ago       131MB
602401143452.dkr.ecr.us-east-1.amazonaws.com/eks/coredns                   v1.8.4-eksbuild.1    b958c05fa7eb   20 months ago       52.8MB
602401143452.dkr.ecr.us-east-1.amazonaws.com/eks/pause                     3.5                  6996f8da07bd   21 months ago       683kB
Cannot perform start session: EOF

Starting session with SessionId: nbbathul-0aa0217fce64ac674
seelog internal error: invalid argument
seelog internal error: invalid argument
seelog internal error: invalid argument
REPOSITORY                                                                 TAG                  IMAGE ID       CREATED             SIZE
026652815482.dkr.ecr.us-east-1.amazonaws.com/prefetching-data-automation   latest               d50f7ccece64   About an hour ago   1.23GB
602401143452.dkr.ecr.us-east-1.amazonaws.com/amazon-k8s-cni-init           v1.10.1-eksbuild.1   b65b61ecb390   15 months ago       276MB
602401143452.dkr.ecr.us-east-1.amazonaws.com/amazon-k8s-cni                v1.10.1-eksbuild.1   407b33483c87   15 months ago       302MB
602401143452.dkr.ecr.us-east-1.amazonaws.com/eks/kube-proxy                v1.21.2-eksbuild.2   5fb0f8c056e6   19 months ago       131MB
602401143452.dkr.ecr.us-east-1.amazonaws.com/eks/pause                     3.5                  6996f8da07bd   21 months ago       683kB
```

* This proves that image has been automatically copied/cached in to new worker node that got created as part of existing EKS cluster.

![Ela](images/Ela.jpg)

### Elamaran Shanmugam

Elamaran (Ela) Shanmugam is a Sr. Container Specialist Solutions Architect with Amazon Web Services. Ela is a Container, Observability and Multi-Account Architecture SME and helps AWS partners and customers to design and build scalable, secure and optimized container workloads on AWS. His passion is building and automating Infrastructure to allow customers to focus more on their business. He is based out of Tampa, Florida and you can reach him on twitter @IamElaShan

### Re Alvarez Parmar

In his role as Containers Specialist Solutions Architect at Amazon Web Services. Re advises engineering teams with modernizing and building distributed services in the cloud. Prior to joining AWS, he spent over 15 years as Enterprise and Software Architect. He is based out of Seattle. You can connect with him on LinkedIn linkedin.com/in/realvarez/

### Naveen Kumar Bathula






