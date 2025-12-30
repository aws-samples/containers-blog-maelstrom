output "configure_kubectl" {
  description = "Configure kubectl"
  value       = "aws eks --region ${local.region} update-kubeconfig --name ${module.eks.cluster_name}"
}

output "msk_bootstrap_brokers_iam" {
  description = "MSK bootstrap brokers for IAM authentication"
  value       = module.msk_cluster.bootstrap_brokers_sasl_iam
}

output "msk_cluster_arn" {
  description = "MSK cluster ARN"
  value       = module.msk_cluster.arn
}

output "producer_pod_identity" {
  description = "Producer Pod Identity details"
  value = {
    role_arn     = module.kafka_producer_pod_identity.iam_role_arn
    service_account = module.kafka_producer_pod_identity.associations["producer"].service_account
    namespace = module.kafka_producer_pod_identity.associations["producer"].namespace
  }
}

output "consumer_pod_identity" {
  description = "Consumer Pod Identity details"
  value = {
    role_arn     = module.kafka_consumer_pod_identity.iam_role_arn
    service_account = module.kafka_consumer_pod_identity.associations["consumer"].service_account
    namespace = module.kafka_consumer_pod_identity.associations["consumer"].namespace
  }
}

output "keda_pod_identity" {
  description = "KEDA Pod Identity details"
  value = {
    role_arn     = module.keda_pod_identity.iam_role_arn
    service_account = module.keda_pod_identity.associations["keda"].service_account
    namespace = module.keda_pod_identity.associations["keda"].namespace
  }
}

output "region" {
  description = "AWS region"
  value       = local.region
}

output "account_id" {
  description = "AWS account ID"
  value       = data.aws_caller_identity.current.account_id
}
