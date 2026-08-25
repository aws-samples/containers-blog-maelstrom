variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "kro_role_arn" {
  description = "ARN of the kro EKS Capability IAM role (from terraform/cluster output)"
  type        = string
}
