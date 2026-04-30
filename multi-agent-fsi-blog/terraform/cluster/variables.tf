variable "aws_region" {
  description = "AWS region to deploy the cluster in"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "EKS cluster name"
  type        = string
  default     = "finops-agents"
}

variable "cluster_version" {
  description = "EKS control-plane version"
  type        = string
  default     = "1.31"
}

variable "vpc_cidr" {
  description = "VPC CIDR block"
  type        = string
  default     = "10.42.0.0/16"
}
