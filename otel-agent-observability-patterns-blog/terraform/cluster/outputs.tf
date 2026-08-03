output "cluster_name" {
  value = module.eks.cluster_name
}

output "cluster_endpoint" {
  value = module.eks.cluster_endpoint
}

output "cluster_certificate_authority_data" {
  value = module.eks.cluster_certificate_authority_data
}

output "region" {
  value = var.region
}

output "kro_role_arn" {
  value = aws_iam_role.kro_capability.arn
}

output "adot_role_arn" {
  value = aws_iam_role.adot.arn
}

output "eks_version" {
  value = var.eks_version
}

output "otel_collector_role_arn" {
  value = aws_iam_role.otel_collector.arn
}
