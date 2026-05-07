output "code_interpreter_id" {
  description = "Code Interpreter ID"
  value       = aws_bedrockagentcore_code_interpreter.code_interpreter.code_interpreter_id
}

output "code_interpreter_arn" {
  description = "Code Interpreter ARN"
  value       = aws_bedrockagentcore_code_interpreter.code_interpreter.code_interpreter_arn
}
