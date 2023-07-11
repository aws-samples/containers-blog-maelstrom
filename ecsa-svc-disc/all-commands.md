*All the provisioning commands, verification and post-configuration commands are put in this markdown for the Blog post - **Implementing Custom Service Discovery for ECS-Anywhere Tasks**

---
### Prerequisites

```
git clone https://github.com/aws-samples/containers-blog-maelstrom.git
cd containers-blog-maelstrom/ecsa-svc-disc
```

---
### Step 1 - Provision the ECS cluster, VPCs/Subnets, EC2 Launch Template and ALB

```
aws cloudformation create-stack --stack-name ecsa-svc-disc-1-ecs-vpc-ec2-alb \
  --template-body file://./cf/ecsa-svc-disc-1-ecs-vpc-ec2-alb.yml \
  --capabilities CAPABILITY_NAMED_IAM --timeout-in-minutes 20 \
  --parameters ParameterKey=SecurityGroupIngressAllowedCidrParameter,ParameterValue=<To be replaced>

aws cloudformation wait stack-create-complete --stack-name ecsa-svc-disc-1-ecs-vpc-ec2-alb
```

**1.**

```
aws ssm get-parameter --name /ecsa/ssmactivation/ActivationInfo --query Parameter.Value --output text

aws ssm get-parameter --name /ecsa/ssmactivation/ActivationId --query Parameter.Value --output text

aws ssm get-parameter --name /ecsa/ssmactivation/ActivationCode --query Parameter.Value --with-decryption --output text
```

**2.**

```
aws ec2 describe-instances --filters 'Name=tag:Name,Values=ECSA-OnPrem-*' 'Name=instance-state-name,Values=running' --query "sort_by(Reservations[].Instances[].{Id:InstanceId,Name:Tags[?Key=='Name']|[0].Value,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress}, &Name)" --output text
```

**3.**

```
aws ecs list-container-instances --cluster ECSA-Demo-Cluster
```

---
### Step 2 - Provision the ECS Task Definitions and Services

```
aws cloudformation create-stack --stack-name ecsa-svc-disc-2-ecs-service-task \
  --template-body file://./cf/ecsa-svc-disc-2-ecs-service-task.yml \
  --capabilities CAPABILITY_NAMED_IAM --timeout-in-minutes 10
  
aws cloudformation wait stack-create-complete --stack-name ecsa-svc-disc-2-ecs-service-task
```

**1.**

```
aws ecs describe-services --cluster ECSA-Demo-Cluster --service Service-DemoApp1 Service-DemoApp2 | jq '.services[] | {serviceArn:.serviceArn, deployments:.deployments[]}'
```

**2.**

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

**1.**
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

**1.**

```
./script/ecsa-svc-disc-show-tg-health.sh
```

**2.**

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
