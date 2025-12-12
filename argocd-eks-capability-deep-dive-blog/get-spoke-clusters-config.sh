# !/bin/bash

# Configure kubectl contexts
aws eks update-kubeconfig --name spoke-cluster-dev \
--region $AWS_REGION_SPOKE_DEV --alias spoke-cluster-dev
aws eks update-kubeconfig --name spoke-cluster-prod \
--region $AWS_REGION_SPOKE_PROD --alias spoke-cluster-prod


# Set environment variable for the cluster's ARNs to be register
export AWS_EKS_HUB_CLUSTER_ARN="arn:aws:eks:${AWS_REGION}:${AWS_ACCOUNT_ID}:cluster/hub-cluster"
export AWS_EKS_SPOKE_DEV_CLUSTER_ARN="arn:aws:eks:${AWS_REGION_SPOKE_DEV}:${AWS_ACCOUNT_ID}:cluster/spoke-cluster-dev"
export AWS_EKS_SPOKE_PROD_CLUSTER_ARN="arn:aws:eks:${AWS_REGION_SPOKE_PROD}:${AWS_ACCOUNT_ID}:cluster/spoke-cluster-prod"
