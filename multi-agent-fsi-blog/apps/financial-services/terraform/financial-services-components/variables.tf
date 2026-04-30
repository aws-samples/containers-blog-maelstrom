variable "project_name" {
  description = "Project name prefix for all resources"
  type        = string
  default     = "financial-services"
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
  description = "EKS cluster name for Pod Identity associations"
  type        = string
}

variable "namespace" {
  description = "Kubernetes namespace hosting the agents and MCP server"
  type        = string
  default     = "financial-services"
}

variable "enable_memory" {
  description = "Provision AgentCore Memory (used by financial-advisor)"
  type        = bool
  default     = true
}

variable "enable_browser" {
  description = "Provision AgentCore Browser (used by market-data)"
  type        = bool
  default     = true
}

variable "enable_code_interpreter" {
  description = "Provision AgentCore Code Interpreter (used by portfolio-analyst and risk-assessment)"
  type        = bool
  default     = true
}

variable "agent_service_accounts" {
  description = "ServiceAccount names for the four Strands agents and the MCP server"
  type        = list(string)
  default = [
    "financial-advisor-sa",
    "portfolio-analyst-sa",
    "risk-assessment-sa",
    "market-data-sa",
    "financial-tools-mcp-sa",
  ]
}
