*All the sample outputs of commands are put in this markdown for the Blog post - **Implementing Custom Service Discovery for ECS-Anywhere Tasks**

---
### Step 1 - Provision the ECS Cluster and Prepare the Activation ID and Activation Code

**1.**

```
{"IamRole":"ECSA-Demo-Cluster-ECSARole","RegistrationLimit":50,"ExpirationDate":"2023-05-21T17:04:27.259Z"}

e1db3452-d0c7-48b0-8f54-2d4317e21f0e

itUspF************** (Partially masked as it is a sensitive data)
```

---
### Step 2 - Provision the VPCs, Subnets, EC2 Launch Template and ALB

**1.**

```
i-0a0f5db07af93d469     ECSA-OnPrem-Proxy       10.0.31.5       18.167.51.161
i-0b6b830d009f1f611     ECSA-OnPrem-Proxy       10.0.33.186     18.162.143.140
i-0cb4428205c6fb63f     ECSA-OnPrem-Proxy       10.0.32.46      43.198.17.79
```

**2.**

```
{"ip":"18.167.51.161"}
```

**3.**

```
i-02bcd1dbfe0c7591a     ECSA-OnPrem-VM  10.0.1.168      None
i-0599e04b00e7e9c97     ECSA-OnPrem-VM  10.0.3.224      None
i-0e81940c6efba2493     ECSA-OnPrem-VM  10.0.2.73       None
```
```
Mon May 22 16:49:33 UTC 2023 1. Setup HTTP Proxy ENV
Mon May 22 16:49:33 UTC 2023 2. Prepare the /tmp/esca.sh for ECS Anywhere agent installation and registration
Mon May 22 16:49:56 UTC 2023 3. Disable EC2 Instance Metadata
Mon May 22 16:49:57 UTC 2023 5. Setup HTTP Proxy for Services
Mon May 22 16:49:57 UTC 2023 4. Install Docker
Mon May 22 16:50:40 UTC 2023 COMPLETED
Mon May 22 16:50:40 UTC 2023 Auto-Registering ECS Anywhere Agent by execuing /tmp/ecsa.sh > /tmp/ecsa.log
Mon May 22 16:51:11 UTC 2023 DONE
```
```
# AWS Account ID are masked as ************
{
  "serviceArn": "arn:aws:ecs:ap-east-1:************:service/ECSA-Demo-Cluster/Service-DemoApp1",
  "deployments": {
    "id": "ecs-svc/2474979950726421586",
    "status": "PRIMARY",
    "taskDefinition": "arn:aws:ecs:ap-east-1:************:task-definition/DemoApp1:1",
    "desiredCount": 1,
    "pendingCount": 0,
    "runningCount": 1,
    "failedTasks": 0,
    "createdAt": "2023-05-23T00:52:52.802000+08:00",
    "updatedAt": "2023-05-23T01:44:01.662000+08:00",
    "launchType": "EXTERNAL",
    "rolloutState": "COMPLETED",
    "rolloutStateReason": "ECS deployment ecs-svc/2474979950726421586 completed."
  }
}
{
  "serviceArn": "arn:aws:ecs:ap-east-1:************:service/ECSA-Demo-Cluster/Service-DemoApp2",
  "deployments": {
    "id": "ecs-svc/7567762855939340968",
    "status": "PRIMARY",
    "taskDefinition": "arn:aws:ecs:ap-east-1:************:task-definition/DemoApp2:1",
    "desiredCount": 3,
    "pendingCount": 0,
    "runningCount": 3,
    "failedTasks": 0,
    "createdAt": "2023-05-23T00:52:54.560000+08:00",
    "updatedAt": "2023-05-23T01:44:08.727000+08:00",
    "launchType": "EXTERNAL",
    "rolloutState": "COMPLETED",
    "rolloutStateReason": "ECS deployment ecs-svc/7567762855939340968 completed."
  }
}
```

---
### Step 3 - Provision the ECS Task Definitions and Services

**1.**

```
# AWS Account ID are masked as ************
{
  "serviceArn": "arn:aws:ecs:ap-east-1:************:service/ECSA-Demo-Cluster/Service-DemoApp1",
  "deployments": {
    "id": "ecs-svc/2474979950726421586",
    "status": "PRIMARY",
    "taskDefinition": "arn:aws:ecs:ap-east-1:************:task-definition/DemoApp1:1",
    "desiredCount": 1,
    "pendingCount": 0,
    "runningCount": 1,
    "failedTasks": 0,
    "createdAt": "2023-05-23T00:52:52.802000+08:00",
    "updatedAt": "2023-05-23T01:44:01.662000+08:00",
    "launchType": "EXTERNAL",
    "rolloutState": "COMPLETED",
    "rolloutStateReason": "ECS deployment ecs-svc/2474979950726421586 completed."
  }
}
{
  "serviceArn": "arn:aws:ecs:ap-east-1:************:service/ECSA-Demo-Cluster/Service-DemoApp2",
  "deployments": {
    "id": "ecs-svc/7567762855939340968",
    "status": "PRIMARY",
    "taskDefinition": "arn:aws:ecs:ap-east-1:************:task-definition/DemoApp2:1",
    "desiredCount": 3,
    "pendingCount": 0,
    "runningCount": 3,
    "failedTasks": 0,
    "createdAt": "2023-05-23T00:52:54.560000+08:00",
    "updatedAt": "2023-05-23T01:44:08.727000+08:00",
    "launchType": "EXTERNAL",
    "rolloutState": "COMPLETED",
    "rolloutStateReason": "ECS deployment ecs-svc/7567762855939340968 completed."
  }
}
```

**2.**

```
# AWS Account ID are masked as ************
ECS Tasks:
------------------------
[
  {
    "taskArn": "arn:aws:ecs:ap-east-1:************:task/ECSA-Demo-Cluster/a3578bfe19c34de5aae679caab599fdc",
    "service": "Service-DemoApp1",
    "containerInstanceId": "aa270abfbbe54b91bb476c097b89a252",
    "desiredStatus": "RUNNING",
    "lastStatus": "RUNNING",
    "hostPort": [
      32770
    ]
  },
  {
    "taskArn": "arn:aws:ecs:ap-east-1:************:task/ECSA-Demo-Cluster/80804e57b28442e28aa248410a98773b",
    "service": "Service-DemoApp2",
    "containerInstanceId": "aa270abfbbe54b91bb476c097b89a252",
    "desiredStatus": "RUNNING",
    "lastStatus": "RUNNING",
    "hostPort": [
      32768,
      32769
    ]
  },
  {
    "taskArn": "arn:aws:ecs:ap-east-1:************:task/ECSA-Demo-Cluster/af7551e83a584d72a147cbb54ae72003",
    "service": "Service-DemoApp2",
    "containerInstanceId": "df65caa34dfe41059ae6cc3acce2327c",
    "desiredStatus": "RUNNING",
    "lastStatus": "RUNNING",
    "hostPort": [
      32768,
      32769
    ]
  },
  {
    "taskArn": "arn:aws:ecs:ap-east-1:************:task/ECSA-Demo-Cluster/bba1e6a2e2db41a59d0e00e824a5428c",
    "service": "Service-DemoApp2",
    "containerInstanceId": "901230153cb94b09854f2d47e6169ffc",
    "desiredStatus": "RUNNING",
    "lastStatus": "RUNNING",
    "hostPort": [
      32770,
      32769
    ]
  }
]

ECS Container Instances:
------------------------
[
  {
    "containerInstanceId": "901230153cb94b09854f2d47e6169ffc",
    "instanceId": "mi-02211c0a333f857a8",
    "status": "ACTIVE",
    "agentConnected": true,
    "runningTasksCount": "1",
    "pendingTasksCount": 0,
    "hostIpAddress": "10.0.3.224"
  },
  {
    "containerInstanceId": "df65caa34dfe41059ae6cc3acce2327c",
    "instanceId": "mi-05725ecc826497835",
    "status": "ACTIVE",
    "agentConnected": true,
    "runningTasksCount": "1",
    "pendingTasksCount": 0,
    "hostIpAddress": "10.0.1.168"
  },
  {
    "containerInstanceId": "aa270abfbbe54b91bb476c097b89a252",
    "instanceId": "mi-0837d7897b4886ff0",
    "status": "ACTIVE",
    "agentConnected": true,
    "runningTasksCount": "2",
    "pendingTasksCount": 0,
    "hostIpAddress": "10.0.2.73"
  }
]
```

---
### Step 4 - Provision the EventBridge, SQS and Lambda Function

```
# AWS Account ID are masked as ************
Setting Target Group Tags
------------------------
DONE

Listing Current Target Group Tags
------------------------
arn:aws:ecs:ap-east-1:************:service/ECSA-Demo-Cluster/Service-DemoApp1
{
    "tags": [
        {
            "key": "ecs-a.lbName",
            "value": "arn:aws:elasticloadbalancing:ap-east-1:************:targetgroup/ECSA-Demo-Cluster-TargetGroup-0/fdfacc0652446c11"
        }
    ]
}

arn:aws:ecs:ap-east-1:************:service/ECSA-Demo-Cluster/Service-DemoApp2
{
    "tags": [
        {
            "key": "ecs-a.lbName",
            "value": "arn:aws:elasticloadbalancing:ap-east-1:************:targetgroup/ECSA-Demo-Cluster-TargetGroup-1/e6162b3123cbaa66 arn:aws:elasticloadbalancing:ap-east-1:************:targetgroup/ECSA-Demo-Cluster-TargetGroup-2/ae7a33533a90d745"
        }
    ]
}
```

**1.**
```
# AWS Account ID are masked as ************
Target Group Health
------------------------
arn:aws:elasticloadbalancing:ap-east-1:************:targetgroup/ECSA-Demo-Cluster-TargetGroup-0/fdfacc0652446c11

arn:aws:elasticloadbalancing:ap-east-1:************:targetgroup/ECSA-Demo-Cluster-TargetGroup-1/e6162b3123cbaa66

arn:aws:elasticloadbalancing:ap-east-1:************:targetgroup/ECSA-Demo-Cluster-TargetGroup-2/ae7a33533a90d745

URL
------------------------
http://ECSA-SvcDisc-ALB-OnPremLB-678673162.ap-east-1.elb.amazonaws.com:8080
http://ECSA-SvcDisc-ALB-OnPremLB-678673162.ap-east-1.elb.amazonaws.com:8081
http://ECSA-SvcDisc-ALB-OnPremLB-678673162.ap-east-1.elb.amazonaws.com:8082
```

---
### Update ECS Service Desired Count and Observe the Registered Targets in ALB Target Groups

```
# AWS Account ID are masked as ************
{
  "serviceArn": "arn:aws:ecs:ap-east-1:************:service/ECSA-Demo-Cluster/Service-DemoApp1",
  "deployments": {
    "id": "ecs-svc/2474979950726421586",
    "status": "PRIMARY",
    "taskDefinition": "arn:aws:ecs:ap-east-1:************:task-definition/DemoApp1:21",
    "desiredCount": 2,
    "pendingCount": 0,
    "runningCount": 2,
    "failedTasks": 0,
    "createdAt": "2023-05-23T00:52:52.802000+08:00",
    "updatedAt": "2023-05-23T01:44:01.662000+08:00",
    "launchType": "EXTERNAL",
    "rolloutState": "COMPLETED",
    "rolloutStateReason": "ECS deployment ecs-svc/2474979950726421586 completed."
  }
}
{
  "serviceArn": "arn:aws:ecs:ap-east-1:************:service/ECSA-Demo-Cluster/Service-DemoApp2",
  "deployments": {
    "id": "ecs-svc/7567762855939340968",
    "status": "PRIMARY",
    "taskDefinition": "arn:aws:ecs:ap-east-1:************:task-definition/DemoApp2:18",
    "desiredCount": 6,
    "pendingCount": 0,
    "runningCount": 6,
    "failedTasks": 0,
    "createdAt": "2023-05-23T00:52:54.560000+08:00",
    "updatedAt": "2023-05-23T01:43:44.789000+08:00",
    "launchType": "EXTERNAL",
    "rolloutState": "COMPLETED",
    "rolloutStateReason": "ECS deployment ecs-svc/7567762855939340968 completed."
  }
}
```

**1.**

```
# AWS Account ID are masked as ************
Target Group Health
------------------------
arn:aws:elasticloadbalancing:ap-east-1:************:targetgroup/ECSA-Demo-Cluster-TargetGroup-0/fdfacc0652446c11
{
  "target": "10.0.3.224:32768",
  "targetHealth": {
    "state": "healthy",
    "reason": null
  }
}
{
  "target": "10.0.2.73:32770",
  "targetHealth": {
    "state": "healthy",
    "reason": null
  }
}

arn:aws:elasticloadbalancing:ap-east-1:************:targetgroup/ECSA-Demo-Cluster-TargetGroup-1/e6162b3123cbaa66
{
  "target": "10.0.3.224:32772",
  "targetHealth": {
    "state": "healthy",
    "reason": null
  }
}
{
  "target": "10.0.1.168:32770",
  "targetHealth": {
    "state": "healthy",
    "reason": null
  }
}
{
  "target": "10.0.2.73:32771",
  "targetHealth": {
    "state": "healthy",
    "reason": null
  }
}
{
  "target": "10.0.2.73:32768",
  "targetHealth": {
    "state": "healthy",
    "reason": null
  }
}
{
  "target": "10.0.1.168:32768",
  "targetHealth": {
    "state": "healthy",
    "reason": null
  }
}
{
  "target": "10.0.3.224:32770",
  "targetHealth": {
    "state": "healthy",
    "reason": null
  }
}

arn:aws:elasticloadbalancing:ap-east-1:************:targetgroup/ECSA-Demo-Cluster-TargetGroup-2/ae7a33533a90d745
{
  "target": "10.0.3.224:32771",
  "targetHealth": {
    "state": "healthy",
    "reason": null
  }
}
{
  "target": "10.0.3.224:32769",
  "targetHealth": {
    "state": "healthy",
    "reason": null
  }
}
{
  "target": "10.0.1.168:32771",
  "targetHealth": {
    "state": "healthy",
    "reason": null
  }
}
{
  "target": "10.0.1.168:32769",
  "targetHealth": {
    "state": "healthy",
    "reason": null
  }
}
{
  "target": "10.0.2.73:32772",
  "targetHealth": {
    "state": "healthy",
    "reason": null
  }
}
{
  "target": "10.0.2.73:32769",
  "targetHealth": {
    "state": "healthy",
    "reason": null
  }
}

URL
------------------------
http://ECSA-SvcDisc-ALB-OnPremLB-678673162.ap-east-1.elb.amazonaws.com:8080
http://ECSA-SvcDisc-ALB-OnPremLB-678673162.ap-east-1.elb.amazonaws.com:8081
http://ECSA-SvcDisc-ALB-OnPremLB-678673162.ap-east-1.elb.amazonaws.com:8082
```

**2.**

```
Node.js backend: Hello! from 
Service-DemoApp1|container0|10.0.2.73:32770
arn:aws:ecs:ap-east-1:************:container/ECSA-Demo-Cluster/a3578bfe19c34de5aae679caab599fdc/8cd31569-491c-4d70-b13c-1d1842766c31
 commit c3e96da
```
```
Node.js backend: Hello! from 
Service-DemoApp1|container0|10.0.3.224:32768
arn:aws:ecs:ap-east-1:************:container/ECSA-Demo-Cluster/f049c03808114a3f8fddd35d67873cb0/36013772-7b44-48f3-a2b4-81b6557a26ef
 commit c3e96da
```

---
### Highlight of Required Modification for On-Premises Load Balancer

---
### Cleaning up

