resource "aws_bedrockagentcore_browser" "browser" {
  name        = "${replace(var.name, "-", "_")}_browser"
  description = var.description

  network_configuration {
    network_mode = var.network_mode
  }

  tags = var.tags
}
