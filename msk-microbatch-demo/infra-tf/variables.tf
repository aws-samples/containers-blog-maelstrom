variable "name" {
  description = "Name prefix for resources"
  type        = string
  default     = "msk-eks-demo-v3"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-east-1"
}

variable "az_count" {
  description = "Number of availability zones to use"
  type        = number
  default     = 2
}

variable "msk_partition_count" {
  description = "Number of partitions for MSK topic"
  type        = number
  default     = 100
}