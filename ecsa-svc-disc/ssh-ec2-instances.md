*Optional steps for SSH into Linux EC2 instances for the Blog post - **Implementing Custom Service Discovery for ECS-Anywhere Tasks**


---

**1.**

After you have provisionsed the CloudFormation stack using, *ecsa-svc-disc-1-ecs-vpc-ec2-alb.yml*, execute the following to get:
- Public IP of Linux EC2 instances of HTTP Proxy (on the 4th column)
- Private IP of Linux EC2 instances of ECS Anywhere agent (on the 3rd column)

```
aws ec2 describe-instances --filters 'Name=tag:Name,Values=ECSA-OnPrem-*' 'Name=instance-state-name,Values=running' --query "sort_by(Reservations[].Instances[].{Id:InstanceId,Name:Tags[?Key=='Name']|[0].Value,PrivateIp:PrivateIpAddress,PublicIp:PublicIpAddress}, &Name)" --output text
```
Sample Output:
```
i-0a0f5db07af93d469     ECSA-OnPrem-Proxy       10.0.31.5       18.167.51.161
i-0b6b830d009f1f611     ECSA-OnPrem-Proxy       10.0.33.186     18.162.143.140
i-0cb4428205c6fb63f     ECSA-OnPrem-Proxy       10.0.32.46      43.198.17.79
i-02bcd1dbfe0c7591a     ECSA-OnPrem-VM  10.0.1.168      None
i-0599e04b00e7e9c97     ECSA-OnPrem-VM  10.0.3.224      None
i-0e81940c6efba2493     ECSA-OnPrem-VM  10.0.2.73       None
```

**2.**

Retrieve the private key of EC2 Key Pair and save it as pem file. You would need the pem file for the *ssh* command.

```
KEYPAIR_ID=$(aws ec2 describe-key-pairs --key-name ECSA-SvcDisc-KeyPair | jq -r '.KeyPairs[].KeyPairId')
aws ssm get-parameter --name /ec2/keypair/$KEYPAIR_ID --with-decryption --query Parameter.Value --output text > ecsa-svcdisc-keypair.pem
chmod 400 ecsa-svcdisc-keypair.pem
```

**3.**

To SSH those Linux EC2 instances of ECS Anywhere agent, you need to:
1. First, SSH into the Linux EC2 instance of HTTP Proxy using their Public IP
2. Second, SSH into the Linux EC2 instance of ECS Anywhere agent using their Private IP

Make sure the *SecurityGroupIngressAllowedCidrParameter*, that you provided as the parameter for CloudFormation template, *ecsa-svc-disc-1-ecs-vpc-ec2-alb.yml*, cover the Public IP range of your testing clients, before you execute the *ssh* command below.

SSH to one of the Linux EC2 instance of HTTP Proxy, by using the *.pem.

```
# In the SSH Session of your local testing client

ssh -i ecsa-svcdisc-keypair.pem ubuntu@18.167.51.161 
# 18.167.51.161 is the Public IP of the 1st Linux EC2 instance of HTTP Proxy
```

In the above SSH session, SSH to one of the Linux EC2 instance of ECS Anywhere agent. Here, you don't need specif pem file, because it has been setup locally in *id_rsa* file in the EC2 instances of HTTP Proxy.

```
# In the SSH Session of Linux EC2 instance of HTTP Proxy

ssh ubuntu@10.0.1.168
# 10.0.1.168 is the Private Ip of the 1st Linux EC2 instance of ECS Anywhere agent
```

**4.**

In the **SSH session of Linux EC2 instance of HTTP Proxy**, execute the following to verify the HTTP Proxy.

Execute *systemctl* command to check status of *squid* service:
```
systemctl status squid
```
Sample Output:
```
● squid.service - Squid Web Proxy Server
     Loaded: loaded (/lib/systemd/system/squid.service; enabled; vendor preset: enabled)
     Active: active (running) since Sun 2023-05-22 16:47:46 UTC; 11min ago
       Docs: man:squid(8)
   Main PID: 2302 (squid)
      Tasks: 4 (limit: 4604)
...
```

Execute the following *curl* command (with -x parameter to specify localhost:3128 as the proxy). If the outbound HTTP request succeeded, it should return Public IP of the EC2 instance as the content.
```
curl -x localhost:3128 https://api.seeip.org/jsonip
```
Sample Output:
```
{"ip":"18.167.51.161"}
```

**5.**

In the **SSH session of Linux EC2 instance of ECS Anywhere agent**, execute the following to verify the ECS Anywhere agent.

Execute the following to verify the status of agent installation, where it is specified in the *UserData* of *AWS::EC2::LaunchTemplate* type in the CloudFormation template. The installation log is written to the */tmp/ecsa.status* locally.
```
cat /tmp/ecsa.status
```
Sample Output:
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

*/tmp/ecsa.log* contains additional logs for ECS Anywhere Agent registration, where you would execute the following to see any errors.
```
grep ERROR /tmp/ecsa.log
```

Execute *systemctl* command to check status of *ecs* service:
```
systemctl status ecs
```
Sample Output:
```
● ecs.service - Amazon Elastic Container Service - container agent
     Loaded: loaded (/lib/systemd/system/ecs.service; enabled; vendor preset: enabled)
    Drop-In: /etc/systemd/system/ecs.service.d
             └─http-proxy.conf
     Active: active (running) since Sun 2023-05-22 16:51:01 UTC; 16min ago
       Docs: https://aws.amazon.com/documentation/ecs/
    Process: 4753 ExecStartPre=/usr/libexec/amazon-ecs-init pre-start (code=exited, status=0/SUCCESS)
   Main PID: 4778 (amazon-ecs-init)
      Tasks: 5 (limit: 9384)
...
```

Query the container instance metadata:
```
curl -s http://localhost:51678/v1/metadata | jq
```
Sample Output:
```
{
  "Cluster": "ECSA-Demo-Cluster",
  "ContainerInstanceArn": ...,
  "Version": "Amazon ECS Agent - v1.72.0 (*ac93073e)"
}
```