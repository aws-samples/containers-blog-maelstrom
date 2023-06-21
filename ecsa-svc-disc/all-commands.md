*All the provisioning commands, verification and post-configuration commands are put in this markdown for the Blog post - **Implementing Custom Service Discovery for ECS-Anywhere Tasks**

---
### Prerequisites

```
git clone https://github.com/aws-samples/containers-blog-maelstrom.git
cd containers-blog-maelstrom/ecsa-svc-disc
```

---
### Step 1 - Provision the ECS Cluster and Prepare the Activation ID and Activation Code

```
aws cloudformation create-stack --stack-name ecsa-svc-disc-ecs-cluster \
  --template-body file://./cf/ecsa-svc-disc-ecs-cluster.yml \
  --capabilities CAPABILITY_NAMED_IAM --timeout-in-minutes 10
```

**1.**

```
aws ssm get-parameter --name /ecsa/ssmactivation/ActivationInfo --query Parameter.Value --output text

aws ssm get-parameter --name /ecsa/ssmactivation/ActivationId --query Parameter.Value --output text

aws ssm get-parameter --name /ecsa/ssmactivation/ActivationCode --query Parameter.Value --with-decryption --output text
```

---
### Step 2 - Provision the VPCs, Subnets, EC2 Launch Template and ALB

```
aws cloudformation create-stack --stack-name ecsa-svc-disc-vpc-ec2-alb \
  --template-body file://./cf/ecsa-svc-disc-vpc-ec2-alb.yml \
  --capabilities CAPABILITY_NAMED_IAM --timeout-in-minutes 10 \
  --parameters ParameterKey=SecurityGroupIngressAllowedCidrParameter,ParameterValue=<To be replaced>
```

**1.**

```
aws ec2 describe-instances --filters 'Name=tag:Name,Values=ECSA-OnPrem-Proxy' 'Name=instance-state-name,Values=running' --query "Reservations[].Instances[].{Id:InstanceId,Name:Tags[?Key=='Name']|[0].Value,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress}" --output text
```

**2.**

```
KEYPAIR_ID=$(aws ec2 describe-key-pairs --key-name ECSA-SvcDisc-KeyPair | jq -r '.KeyPairs[].KeyPairId')
aws ssm get-parameter --name /ec2/keypair/$KEYPAIR_ID --with-decryption --query Parameter.Value --output text > ecsa-svcdisc-keypair.pem
chmod 400 ecsa-svcdisc-keypair.pem

ssh -i ecsa-svcdisc-keypair.pem ubuntu@18.167.51.161 # Public IP of the 1st Linux EC2 instance of HTTP Proxy above
```
```
curl -x localhost:3128 https://api.ipify.org?format=json
```

**3.**

```
aws autoscaling set-desired-capacity --auto-scaling-group-name ECSA-OnPrem-VM-ASG --desired-capacity 3
```
```
aws ec2 describe-instances --filters 'Name=tag:Name,Values=ECSA-OnPrem-VM' 'Name=instance-state-name,Values=running' --query "Reservations[].Instances[].{Id:InstanceId,Name:Tags[?Key=='Name']|[0].Value,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress}" --output text
```
```
# In the SSH Session of 1st Linux EC2 instance of HTTP Proxy (18.167.51.161)
ssh ubuntu@10.0.1.168
```
```
tail -f /tmp/ecsa.status
```
```
aws ecs list-container-instances --cluster ECSA-Demo-Cluster
```

---
### Step 3 - Provision the ECS Task Definitions and Services

```
aws cloudformation create-stack --stack-name ecsa-svc-disc-ecs-service-task \
  --template-body file://./cf/ecsa-svc-disc-ecs-service-task.yml \
  --capabilities CAPABILITY_NAMED_IAM --timeout-in-minutes 10
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
### Step 4 - Provision the EventBridge, SQS and Lambda Function

```
aws cloudformation create-stack --stack-name ecsa-svc-disc-sqs-lambda \
  --template-body file://./cf/ecsa-svc-disc-sqs-lambda.yml \
  --capabilities CAPABILITY_NAMED_IAM --timeout-in-minutes 10
```
```
pushd lambda
zip lambda.zip *.mjs
aws lambda update-function-code --function-name ECSA-Demo-Cluster-Lambda-ProcessEvent --zip-file fileb://./lambda.zip | jq '{FunctionArn:.FunctionArn,CodeSize:.CodeSize}'
popd
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
aws ecs list-container-instances --cluster ECSA-Demo-Cluster
```
```
aws ecs deregister-container-instance --cluster ECSA-Demo-Cluster \
    --container-instance <Container Instance ARN> \
    --force
```
```
aws cloudformation delete-stack --stack-name ecsa-svc-disc-sqs-lambda
aws cloudformation delete-stack --stack-name ecsa-svc-disc-ecs-service-task
aws cloudformation delete-stack --stack-name ecsa-svc-disc-sqs-vpc-ec2-alb
aws cloudformation delete-stack --stack-name ecsa-svc-disc-sqs-ecs-cluster
```
