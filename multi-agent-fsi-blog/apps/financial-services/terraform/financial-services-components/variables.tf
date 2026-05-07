variable "project_name" {
  description = "Per-agent project prefix (e.g. financial-services-financial-advisor). AWS resource names are derived from this — it must be unique per Terraform CR to avoid AgentCore name collisions across agents."
  type        = string
}

variable "aws_region" {
  description = "AWS region"
  type        = string
  default     = "us-west-2"
}

variable "network_mode" {
  description = "Network mode for Agent Core tools (PUBLIC, VPC, or SANDBOX)"
  type        = string
  default     = "PUBLIC"
}

variable "eks_cluster_name" {
  description = "EKS cluster name for the Pod Identity association"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace hosting this agent"
  type        = string
  default     = "financial-services"
}

variable "agent_sa" {
  description = "ServiceAccount name for this one agent. Creates exactly one Pod Identity association binding this SA to the per-agent IAM role."
  type        = string
}

variable "enable_memory" {
  description = "Provision a dedicated AgentCore Memory for this agent"
  type        = bool
  default     = false
}

variable "enable_browser" {
  description = "Provision a dedicated AgentCore Browser for this agent"
  type        = bool
  default     = false
}

variable "enable_code_interpreter" {
  description = "Provision a dedicated AgentCore Code Interpreter for this agent"
  type        = bool
  default     = false
}
