output "cluster_name" {
  description = "EKS cluster name"
  value       = module.eks.cluster_name
}

output "cluster_endpoint" {
  description = "EKS API endpoint"
  value       = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  description = "Base64-encoded CA cert for the cluster"
  value       = module.eks.cluster_certificate_authority_data
}

output "oidc_provider_arn" {
  description = "OIDC provider ARN (for IRSA fallback; Pod Identity is preferred)"
  value       = module.eks.oidc_provider_arn
}

output "region" {
  description = "AWS region"
  value       = var.aws_region
}

output "vpc_id" {
  description = "VPC ID hosting the cluster"
  value       = module.vpc.vpc_id
}

output "private_subnet_ids" {
  description = "Private subnet IDs (workload + control-plane)"
  value       = module.vpc.private_subnets
}

output "kubeconfig_command" {
  description = "Run this to get kubeconfig for the new cluster"
  value       = "aws eks update-kubeconfig --region ${var.aws_region} --name ${module.eks.cluster_name}"
}

output "tf_runner_role_arn" {
  description = "IAM role ARN bound to the flux-system/tf-runner ServiceAccount via Pod Identity"
  value       = aws_iam_role.tf_runner.arn
}

output "tf_runner_role_name" {
  description = "IAM role name for the Tofu Controller runner pod"
  value       = aws_iam_role.tf_runner.name
}

output "tfstate_bucket" {
  description = "S3 bucket backing in-cluster Terraform state"
  value       = aws_s3_bucket.tfstate.id
}

output "tfstate_lock_table" {
  description = "DynamoDB table backing in-cluster Terraform state locks"
  value       = aws_dynamodb_table.tfstate_locks.id
}
