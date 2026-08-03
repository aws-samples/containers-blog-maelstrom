# Amazon Managed Grafana workspace
resource "aws_grafana_workspace" "agents" {
  name                     = "${var.cluster_name}-agent-dashboards"
  account_access_type      = "CURRENT_ACCOUNT"
  authentication_providers = ["AWS_SSO"]
  permission_type          = "SERVICE_MANAGED"
  role_arn                 = aws_iam_role.grafana.arn

  data_sources = ["PROMETHEUS"]

  tags = var.tags
}

# IAM role for Grafana to query AMP
resource "aws_iam_role" "grafana" {
  name = "${var.cluster_name}-grafana"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "grafana.amazonaws.com"
      }
      Action = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_role_policy" "grafana_amp_query" {
  name = "grafana-amp-query"
  role = aws_iam_role.grafana.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "aps:QueryMetrics",
        "aps:GetSeries",
        "aps:GetLabels",
        "aps:GetMetricMetadata"
      ]
      Resource = aws_prometheus_workspace.agents.arn
    }]
  })
}

# NOTE: AMP data source configuration in Grafana is done manually via the
# Grafana UI or API after workspace creation. The Grafana Terraform provider
# (grafana/grafana) can automate this if needed — see:
# https://registry.terraform.io/providers/grafana/grafana/latest/docs

output "grafana_workspace_endpoint" {
  value = aws_grafana_workspace.agents.endpoint
}
