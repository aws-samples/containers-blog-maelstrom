resource "aws_prometheus_workspace" "agents" {
  alias = "${var.cluster_name}-agent-metrics"
  tags  = var.tags
}

output "amp_workspace_endpoint" {
  value = aws_prometheus_workspace.agents.prometheus_endpoint
}

output "amp_remote_write_endpoint" {
  value = "${aws_prometheus_workspace.agents.prometheus_endpoint}api/v1/remote_write"
}

output "amp_workspace_id" {
  value = aws_prometheus_workspace.agents.id
}
