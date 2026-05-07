output "memory_id" {
  description = "AgentCore Memory ID (consumed by financial-advisor)"
  value       = var.enable_memory ? module.memory[0].memory_id : ""
}

output "browser_id" {
  description = "AgentCore Browser ID (consumed by market-data)"
  value       = var.enable_browser ? module.browser[0].browser_id : ""
}

output "code_interpreter_id" {
  description = "AgentCore Code Interpreter ID (consumed by portfolio-analyst + risk-assessment)"
  value       = var.enable_code_interpreter ? module.code_interpreter[0].code_interpreter_id : ""
}

output "agent_role_arn" {
  description = "IAM role ARN assumed by every agent pod via Pod Identity"
  value       = aws_iam_role.financial_agent_role.arn
}

output "namespace" {
  description = "Kubernetes namespace for the stack"
  value       = var.namespace
}
