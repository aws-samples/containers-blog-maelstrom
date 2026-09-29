# ---------------------------------------------------------------
# Bifrost IAM — only Bifrost needs Bedrock permissions.
# Agents call Bifrost (HTTP), not Bedrock directly. Bifrost runs in
# the observability namespace as a shared platform service, so its
# Pod Identity association is scoped there (not to agents).
# ---------------------------------------------------------------
resource "aws_iam_role" "bifrost" {
  name = "${var.cluster_name}-bifrost"

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

resource "aws_iam_role_policy" "bifrost_bedrock" {
  name = "bifrost-bedrock-access"
  role = aws_iam_role.bifrost.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream", "bedrock:ListFoundationModels"]
      Resource = "*"
    }]
  })
}

resource "aws_eks_pod_identity_association" "bifrost" {
  cluster_name = module.eks.cluster_name
  # Bifrost is a shared platform service and runs in the observability
  # namespace (with Langfuse and the OTEL Collector), not in agents.
  namespace       = "observability"
  service_account = "bifrost"
  role_arn        = aws_iam_role.bifrost.arn
}

# ---------------------------------------------------------------
# Agent IAM — agents do NOT need Bedrock permissions.
# They talk to Bifrost over HTTP; Bifrost handles model calls.
# This role is left for any future agent-specific AWS permissions
# (e.g. S3 access for tool results, DynamoDB for memory).
# ---------------------------------------------------------------
resource "aws_iam_role" "agents" {
  name = "${var.cluster_name}-agents"

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

# No Bedrock policy attached — agents call Bifrost, not Bedrock.

resource "aws_eks_pod_identity_association" "research_agent" {
  cluster_name    = module.eks.cluster_name
  namespace       = "agents"
  service_account = "research-agent-sa"
  role_arn        = aws_iam_role.agents.arn
}

resource "aws_eks_pod_identity_association" "data_agent" {
  cluster_name    = module.eks.cluster_name
  namespace       = "agents"
  service_account = "data-agent-sa"
  role_arn        = aws_iam_role.agents.arn
}
