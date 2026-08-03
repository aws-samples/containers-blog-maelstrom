# IAM role for the OTEL Collector to write metrics to AMP
resource "aws_iam_role" "otel_collector" {
  name = "${var.cluster_name}-otel-collector"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = ["sts:AssumeRole", "sts:TagSession"]
    }]
  })
}

resource "aws_iam_role_policy" "otel_collector_amp" {
  name = "otel-collector-amp-write"
  role = aws_iam_role.otel_collector.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = [
        "aps:RemoteWrite",
        "aps:GetSeries",
        "aps:GetLabels",
        "aps:GetMetricMetadata"
      ]
      Resource = aws_prometheus_workspace.agents.arn
    }]
  })
}

# Bind the IAM role to the OTEL Collector service account via Pod Identity
resource "aws_eks_pod_identity_association" "otel_collector" {
  cluster_name    = module.eks.cluster_name
  namespace       = "observability"
  service_account = "otel-collector-opentelemetry-collector"
  role_arn        = aws_iam_role.otel_collector.arn
}
