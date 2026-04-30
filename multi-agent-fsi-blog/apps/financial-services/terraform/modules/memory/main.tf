resource "aws_bedrockagentcore_memory" "memory" {
  name                  = "${replace(var.name, "-", "_")}_memory"
  description           = var.description
  event_expiry_duration = var.event_expiry_duration

  tags = var.tags
}
