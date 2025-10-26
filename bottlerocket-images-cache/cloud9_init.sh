#!/bin/bash
# Initialize region
if [ -z "$AWS_DEFAULT_REGION" ]; then
    echo "Setting default region to us-east-1"
    AWS_DEFAULT_REGION="us-east-1"
fi
export AWS_REGION="$AWS_DEFAULT_REGION"
echo "Using region: $AWS_REGION"
# Test AWS CLI with region
if ! aws sts get-caller-identity --region "$AWS_REGION"; then
    echo "Failed to validate AWS credentials"
    exit 1
fi
# Get Account ID
ACCOUNT_ID=$(aws sts get-caller-identity --region "$AWS_REGION" --query "Account" --output text)
echo "Account ID: $ACCOUNT_ID"
# Get Availability Zones
AZS=$(aws ec2 describe-availability-zones --region "$AWS_REGION" --query "AvailabilityZones[].ZoneName" --output text)
echo "Available AZs: $AZS"
# Install kubectl
curl --silent --location -o kubectl \
    https://amazon-eks.s3.us-west-2.amazonaws.com/1.19.6/2021-01-05/bin/linux/amd64/kubectl
chmod +x kubectl
mkdir -p $HOME/bin && mv kubectl $HOME/bin/
export PATH=$PATH:$HOME/bin
# Set environment variables
{
    echo "export AWS_REGION=\"$AWS_REGION\""
    echo "export ACCOUNT_ID=\"$ACCOUNT_ID\""
    echo "export AZS=($AZS)"
    echo "export PATH=\$PATH:\$HOME/bin"
} >> ~/.bash_profile
# Install eksctl
curl --silent --location "https://github.com/weaveworks/eksctl/releases/latest/download/eksctl_$(uname -s)_amd64.tar.gz" | tar xz -C /tmp
mkdir -p $HOME/bin
mv -v /tmp/eksctl $HOME/bin/
# Install helm
curl -sSL https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3 | bash
# Setup completions
{
    kubectl completion bash
    eksctl completion bash
    helm completion bash
} >> ~/.bash_completion
source ~/.bash_completion
source ~/.bash_profile
# Verify installations
echo "Verifying installations..."
kubectl version --client
eksctl version
helm version --short
echo "Setup complete!"