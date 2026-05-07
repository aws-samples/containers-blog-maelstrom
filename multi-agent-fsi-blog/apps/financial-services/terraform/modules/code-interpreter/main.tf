resource "aws_bedrockagentcore_code_interpreter" "code_interpreter" {
  name        = "${replace(var.name, "-", "_")}_code_interpreter"
  description = var.description

  network_configuration {
    network_mode = var.network_mode
  }

  tags = var.tags
}
