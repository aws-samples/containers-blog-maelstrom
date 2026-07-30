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

output "ack_capability_role_arn" {
  description = "IAM role ARN assumed by the ACK EKS Capability. Every ACK service controller (bedrockagentcorecontrol, iam, eks) authenticates to AWS under this role."
  value       = aws_iam_role.ack_capability.arn
}

output "ack_capability_arn" {
  description = "ARN of the ACK EKS Capability"
  value       = aws_eks_capability.ack.arn
}

output "kro_capability_arn" {
  description = "ARN of the kro EKS Capability (reconciles the AgentCore ResourceGraphDefinitions)"
  value       = aws_eks_capability.kro.arn
}

output "litellm_bedrock_role_arn" {
  description = "IAM role ARN bound to litellm/litellm via Pod Identity for direct Bedrock model invocation."
  value       = aws_iam_role.litellm_bedrock.arn
}
