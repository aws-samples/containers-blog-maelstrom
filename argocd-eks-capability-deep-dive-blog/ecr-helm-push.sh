# !/bin/bash
# Get account ID
export AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query Account --output text)

# Create ECR repository for Helm charts
aws ecr create-repository \
  --repository-name helm-charts/helm-guestbook \
  --region $AWS_REGION

# Authenticate Helm with ECR
aws ecr get-login-password --region $AWS_REGION | \
  helm registry login \
    --username AWS \
    --password-stdin \
    ${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com

# Clone example apps and package the chart
git clone https://github.com/argoproj/argocd-example-apps
helm package argocd-example-apps/helm-guestbook

# Push to ECR
helm push helm-guestbook-0.1.0.tgz \
  oci://${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/helm-charts/

echo "Helm chart pushed to ECR: oci://${AWS_ACCOUNT_ID}.dkr.ecr.${AWS_REGION}.amazonaws.com/helm-charts/helm-guestbook:0.1.0"
