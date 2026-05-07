output "memory_id" {
  description = "Memory ID"
  value       = aws_bedrockagentcore_memory.memory.id
}

output "memory_arn" {
  description = "Memory ARN"
  value       = aws_bedrockagentcore_memory.memory.arn
}
