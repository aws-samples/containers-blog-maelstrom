printf "Getting VPC ID: "
JOF_VPC_ID=$(aws eks describe-cluster --name jenkins-on-fargate \
  --region $JOF_REGION \
  --query "cluster.resourcesVpcConfig.vpcId" \
  --output text)

printf "$JOF_VPC_ID\n"

printf "Gettting VPC CIDR block: "
JOF_CIDR_BLOCK=$(aws ec2 describe-vpcs --vpc-ids $JOF_VPC_ID \
  --query "Vpcs[].CidrBlock" \
  --region $JOF_REGION \
  --output text)
printf "$JOF_CIDR_BLOCK\n"

printf "Creating a security Group for EFS: "
JOF_EFS_SG_ID=$(aws ec2 create-security-group \
  --region $JOF_REGION \
  --description Jenkins-on-Fargate \
  --group-name Jenkins-on-Fargate \
  --vpc-id $JOF_VPC_ID \
  --query 'GroupId' \
  --output text)
printf "$JOF_EFS_SG_ID\n"

printf "Configuring the security group to allow ingress NFS traffic from the VPC\n"
aws ec2 authorize-security-group-ingress \
  --group-id $JOF_EFS_SG_ID \
  --protocol tcp \
  --port 2049 \
  --cidr $JOF_CIDR_BLOCK \
  --region $JOF_REGION \
  --output text

printf "Creating an EFS filesystem..."
export JOF_EFS_FS_ID=$(aws efs create-file-system \
  --creation-token Jenkins-on-Fargate \
  --performance-mode generalPurpose \
  --throughput-mode bursting \
  --region $JOF_REGION \
  --tags Key=Name,Value=JenkinsVolume \
  --encrypted \
  --output text \
  --query "FileSystemId")
printf "done\n"

printf "Waiting for 10 seconds\n"
sleep 10

printf "Creating mount targets..."
for subnet in $(aws eks describe-fargate-profile \
  --output text --cluster-name jenkins-on-fargate\
  --region $JOF_REGION  \
  --fargate-profile-name fp-default  \
  --query "fargateProfile.subnets"); \
do (aws efs create-mount-target \
  --file-system-id $JOF_EFS_FS_ID \
  --subnet-id $subnet \
  --security-group $JOF_EFS_SG_ID \
  --region $JOF_REGION --output text); \
done 
printf "done\n"

exit

printf "Creating EFS access points..."
JOF_EFS_AP=$(aws efs create-access-point \
  --file-system-id $JOF_EFS_FS_ID \
  --posix-user Uid=1000,Gid=1000 \
  --root-directory "Path=/jenkins,CreationInfo={OwnerUid=1000,OwnerGid=1000,Permissions=777}" \
  --region $JOF_REGION \
  --query 'AccessPointId' \
  --output text)
printf "done\n"

