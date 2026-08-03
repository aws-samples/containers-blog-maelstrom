variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "amp_remote_write_endpoint" {
  description = "AMP remote write endpoint URL"
  type        = string
  default     = ""
}

variable "kro_role_arn" {
  description = "ARN of the kro EKS Capability IAM role (from terraform/cluster output)"
  type        = string
}

variable "adot_role_arn" {
  description = "ARN of the ADOT IAM role (from terraform/cluster output)"
  type        = string
}
