#!/bin/bash
set -e

# Disable AWS CLI pager
export AWS_PAGER=""

echo ""
echo "=== Cleaning Up Resources ==="
echo ""

# Load environment variables
export $(grep -v '^#' .env | xargs)

# Delete ECR repositories
echo ""
echo "Deleting ECR repositories..."
echo ""

aws ecr delete-repository --repository-name $IMAGE_NAME_PRODUCER --region $AWS_REGION --force 2>/dev/null && \
  echo "✓ Deleted ECR repository: $IMAGE_NAME_PRODUCER" || \
  echo "✗ ECR repository not found or already deleted: $IMAGE_NAME_PRODUCER"

aws ecr delete-repository --repository-name $IMAGE_NAME_CONSUMER --region $AWS_REGION --force 2>/dev/null && \
  echo "✓ Deleted ECR repository: $IMAGE_NAME_CONSUMER" || \
  echo "✗ ECR repository not found or already deleted: $IMAGE_NAME_CONSUMER"

# Destroy Terraform infrastructure
echo ""
echo "Destroying Terraform infrastructure..."
echo ""

cd infra-tf
terraform destroy -auto-approve

echo ""
echo "=== Cleanup Complete ==="
echo ""
