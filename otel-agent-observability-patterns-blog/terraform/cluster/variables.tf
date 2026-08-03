variable "cluster_name" {
  description = "Name of the EKS cluster"
  type        = string
  default     = "agent-observability"
}

variable "region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "tags" {
  description = "Common tags for all resources"
  type        = map(string)
  default = {
    Project = "otel-agent-observability"
    Blog    = "containers-blog-maelstrom"
  }
}

variable "eks_version" {
  description = "EKS cluster Kubernetes version"
  type        = string
  default     = "1.35"
}
