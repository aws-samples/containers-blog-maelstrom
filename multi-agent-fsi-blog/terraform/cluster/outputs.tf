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

output "crossplane_provider_role_arn" {
  description = "IAM role ARN bound to crossplane-system/crossplane-aws-provider-sa via Pod Identity. Used by every Upbound AWS provider (aws-bedrockagentcore, aws-iam, aws-eks) to authenticate to AWS."
  value       = aws_iam_role.crossplane_provider.arn
}

output "crossplane_provider_role_name" {
  description = "Crossplane AWS provider IAM role name"
  value       = aws_iam_role.crossplane_provider.name
}
