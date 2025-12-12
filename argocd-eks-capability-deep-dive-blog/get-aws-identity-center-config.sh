# !/bin/bash

# Get your Identity Center instance details
export AWS_IDC_INSTANCE_ARN=$(aws sso-admin list-instances \
  --query 'Instances[0].InstanceArn' \
  --output text \
  --region $AWS_IDC_REGION)

export AWS_IDC_INSTANCE_ID=$(aws sso-admin list-instances \
  --query 'Instances[0].IdentityStoreId' \
  --output text \
  --region $AWS_IDC_REGION)

# Get the group ID for Argo CD administrators
# Replace 'eks-argo-cd-admins' with your Identity Center group name
export AWS_IDC_GROUP_NAME_ADMIN="eks-argo-cd-admins"
export AWS_IDC_GROUP_ID_ADMIN=$(aws identitystore list-groups \
  --identity-store-id $AWS_IDC_INSTANCE_ID \
  --query "Groups[?DisplayName==\`${AWS_IDC_GROUP_NAME_ADMIN}\`].GroupId | [0]" \
  --output text \
  --region $AWS_IDC_REGION)

# Get the group ID for Argo CD developers
# Replace 'eks-argo-cd-developers' with your Identity Center group name
export AWS_IDC_GROUP_NAME_VIEWER="eks-argo-cd-developers"
export AWS_IDC_GROUP_ID_DEVELOPER=$(aws identitystore list-groups \
  --identity-store-id $AWS_IDC_INSTANCE_ID \
  --query "Groups[?DisplayName==\`${AWS_IDC_GROUP_NAME_VIEWER}\`].GroupId | [0]" \
  --output text \
  --region $AWS_IDC_REGION)

echo "variable AWS_IDC_INSTANCE_ARN stores the Identity Center Instance ARN: $AWS_IDC_INSTANCE_ARN"
echo "variable AWS_IDC_GROUP_ID_ADMIN stores the Admin Group ID: $AWS_IDC_GROUP_ID_ADMIN"
echo "variable AWS_IDC_GROUP_ID_DEVELOPER stores the Developer Group ID: $AWS_IDC_GROUP_ID_DEVELOPER"

