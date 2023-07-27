*All the provisioning commands, verification and post-configuration commands are put in this markdown for the Blog post - **Implementing Custom Service Discovery for ECS-Anywhere Tasks**

---
### Prerequisites

```
git clone https://github.com/aws-samples/containers-blog-maelstrom.git
cd containers-blog-maelstrom/ecsa-svc-disc
```
In summary, there are totally 3 steps, for the provisioning of 3 CloudFormation templates:


###### Step 1 - Provision the ECS cluster, VPCs/Subnets, EC2 Launch Template and ALB

Provision the ECS cluster for the Amazon ECS Anywhere, and prepare the Activation ID  and Activation Code for ECS Anywhere agent registration. This step also provision the core infrastructure of this post, including VPCs, Subnets, EC2 Launch Template and ALB. There are 2 Auto Scaling Group (ASG), 1 for the Linux EC2 instances of HTTP proxy (in Public subnet); 1 for the Linux EC2 instances of ECS Anywhere agent (in Private subnet).

The provisioned ALB target groups would initially have no registered targets. The Lambda function (to be provisioned in Step 3) would register / deregister against those ALB target groups later.

###### Step 2 - Provision the ECS task definitions and services

Provision the sample ECS task definitions and services for the ECS cluster provisioned in Step 1. The launch type of corresponding ECS tasks is set to EXTERNAL, so that those tasks would be managed by ECS Anywhere agents, running in the Linux EC2 instances provisioned in Step 1.

###### Step 3 - Provision the EventBridge event bus, SQS queue and Lambda function

Provision EventBridge event bus and SQS queue, so that they would fired and stored the ECS Task State Change events. Provision the Lambda function, to process those events from SQS queue in batch mode, as well as the required VPC endpoints for the Lambda function.

---
### Step 1 - Provision the ECS cluster, VPCs/Subnets, EC2 Launch Template and ALB

```
aws cloudformation create-stack --stack-name ecsa-svc-disc-1-ecs-vpc-ec2-alb \
  --template-body file://./cf/ecsa-svc-disc-1-ecs-vpc-ec2-alb.yml \
  --capabilities CAPABILITY_NAMED_IAM --timeout-in-minutes 20 \
  --parameters ParameterKey=SecurityGroupIngressAllowedCidrParameter,ParameterValue=<To be replaced>

aws cloudformation wait stack-create-complete --stack-name ecsa-svc-disc-1-ecs-vpc-ec2-alb
```

###### <ins>Additional</ins> verification

**1.**

Execute the following to verify if the parameters from Parameter Store are persisted correctly. The 1st parameter, /ecsa/ssmactivation/ActivationInfo, include the IAM Role for ECS Anywhere/SSM agents, as well as the Registration Limit and Expiration Date, where both of them are configurable as CloudFormation parameters.

```
aws ssm get-parameter --name /ecsa/ssmactivation/ActivationInfo --query Parameter.Value --output text

aws ssm get-parameter --name /ecsa/ssmactivation/ActivationId --query Parameter.Value --output text

aws ssm get-parameter --name /ecsa/ssmactivation/ActivationCode --query Parameter.Value --with-decryption --output text
```

**2.**

Execute the following to verify 3 Linux EC2 instances of HTTP proxy and 3 Linux EC2 instances of ECS Anywhere agent are provisioned successfully:

```
aws ec2 describe-instances --filters 'Name=tag:Name,Values=ECSA-OnPrem-*' 'Name=instance-state-name,Values=running' --query "sort_by(Reservations[].Instances[].{Id:InstanceId,Name:Tags[?Key=='Name']|[0].Value,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress}, &Name)" --output text
```

**3.**

An ECS container instance is an EC2 instance that is running the agent and has been registered with an ECS Cluster. 

Execute the following command to list container instances, that help to verify if the 3 ECS Anywhere agents (in 3 Linux EC2 instances) are registered successfully. 

Because we have provisioned 3 Linux EC2 instances for ECS Anywhere agents, you should observe 3 container instances in the output.

```
aws ecs list-container-instances --cluster ECSA-Demo-Cluster
```

**4.**

In the case, you want to SSH into the Linux EC2 instances (either for HTTP proxy or for ECS Anywhere agent) and see the logs for additional informations, you can refer to markdown, *ssh-ec2-instances.md*, for those commands.

---
### Step 2 - Provision the ECS Task Definitions and Services

```
aws cloudformation create-stack --stack-name ecsa-svc-disc-2-ecs-service-task \
  --template-body file://./cf/ecsa-svc-disc-2-ecs-service-task.yml \
  --capabilities CAPABILITY_NAMED_IAM --timeout-in-minutes 10
  
aws cloudformation wait stack-create-complete --stack-name ecsa-svc-disc-2-ecs-service-task
```

###### <ins>Additional</ins> verification

**1.**

Execute the following command, and verify if the value of *runningCount* equals the value of *desiredCount* for both ECS services.

```
aws ecs describe-services --cluster ECSA-Demo-Cluster --service Service-DemoApp1 Service-DemoApp2 | jq '.services[] | {serviceArn:.serviceArn, deployments:.deployments[]}'
```

**2.**

Execute the following command to print more details information about the ECS services and ECS tasks deployed.

Because the network mode is set to Bridge in ECS task definition, you should observe the *hostPort*, is assigned from the range, 32768 - 61000, from the output.

For the ECS tasks under *Service-DemoApp1*, there is only 1 *hostPort* for the *container0*. For the ECS tasks under *Service-DemoApp2*, there are 2 *hostPort* - because there are 2 containers defined in the task definition: *container1* and *container2*. 

For *runningTasksCount* under ECS Container Instances, the total added-up value should be 4, for 3 container instances - because the *desiredCount* of *Service-DemoApp1* is 1, while *desiredCount* of *Service-DemoApp2* is 3.

```
chmod 755 script/ecsa-svc-disc-show-tasks.sh
./script/ecsa-svc-disc-show-tasks.sh
```

---
### Step 3 - Provision the EventBridge, SQS and Lambda Function

```
aws cloudformation create-stack --stack-name ecsa-svc-disc-3-sqs-lambda \
  --template-body file://./cf/ecsa-svc-disc-3-sqs-lambda.yml \
  --capabilities CAPABILITY_NAMED_IAM --timeout-in-minutes 10
  
aws cloudformation wait stack-create-complete --stack-name ecsa-svc-disc-3-sqs-lambda
```
```
cd lambda
zip lambda.zip *.mjs
aws lambda update-function-code --function-name ECSA-Demo-Cluster-Lambda-ProcessEvent --zip-file fileb://./lambda.zip | jq '{FunctionArn:.FunctionArn,CodeSize:.CodeSize}'
cd ..
```
```
chmod 755 script/ecsa-svc-disc-set-tg-tags.sh
./script/ecsa-svc-disc-set-tg-tags.sh
```

###### Verification and post-configuration

```
chmod 755 script/ecsa-svc-disc-show-tg-health.sh
./script/ecsa-svc-disc-show-tg-health.sh
```

---
### Update ECS Service Desired Count and Observe the Registered Targets in ALB Target Groups

```
aws ecs update-service --cluster ECSA-Demo-Cluster --service Service-DemoApp1 --desired-count 2 | jq '.service | {serviceArn:.serviceArn, status:.status, desiredCount:.desiredCount, runningCount:.runningCount}'
aws ecs update-service --cluster ECSA-Demo-Cluster --service Service-DemoApp2 --desired-count 6 | jq '.service | {serviceArn:.serviceArn, status:.status, desiredCount:.desiredCount, runningCount:.runningCount}'

aws ecs describe-services --cluster ECSA-Demo-Cluster --service Service-DemoApp1 Service-DemoApp2 | jq '.services[] | {serviceArn:.serviceArn, deployments:.deployments[]}'
```

###### Verification and post-configuration


```
./script/ecsa-svc-disc-show-tg-health.sh
```

```
curl http://ECSA-SvcDisc-ALB-OnPremLB-<suffix>.<aws region>.elb.amazonaws.com:8080
curl http://ECSA-SvcDisc-ALB-OnPremLB-<suffix>.<aws region>.elb.amazonaws.com:8081
curl http://ECSA-SvcDisc-ALB-OnPremLB-<suffix>.<aws region>.elb.amazonaws.com:8082
```

---
### Highlight of Required Modification for On-Premises Load Balancer

```
//import * as lb from './lb-alb.mjs';
import * as lb from './lb-your-onprem-ld.mjs';
```

---
### Cleaning up

```
aws cloudformation delete-stack --stack-name ecsa-svc-disc-3-sqs-lambda
aws cloudformation wait stack-delete-complete --stack-name ecsa-svc-disc-3-sqs-lambda

aws cloudformation delete-stack --stack-name ecsa-svc-disc-2-ecs-service-task
aws cloudformation wait stack-delete-complete --stack-name ecsa-svc-disc-2-ecs-service-task

aws cloudformation delete-stack --stack-name ecsa-svc-disc-1-ecs-vpc-ec2-alb
aws cloudformation wait stack-delete-complete --stack-name ecsa-svc-disc-1-ecs-vpc-ec2-alb
```
