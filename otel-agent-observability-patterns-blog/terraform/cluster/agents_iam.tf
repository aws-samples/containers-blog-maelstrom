# IAM role for agent pods to call Bedrock
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

resource "aws_iam_role_policy" "agents_bedrock" {
  name = "agents-bedrock-access"
  role = aws_iam_role.agents.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect   = "Allow"
      Action   = ["bedrock:InvokeModel", "bedrock:InvokeModelWithResponseStream"]
      Resource = "*"
    }]
  })
}

# Bind to research-agent service account
resource "aws_eks_pod_identity_association" "research_agent" {
  cluster_name    = module.eks.cluster_name
  namespace       = "agents"
  service_account = "research-agent-sa"
  role_arn        = aws_iam_role.agents.arn
}

# Bind to data-agent service account
resource "aws_eks_pod_identity_association" "data_agent" {
  cluster_name    = module.eks.cluster_name
  namespace       = "agents"
  service_account = "data-agent-sa"
  role_arn        = aws_iam_role.agents.arn
}

# Bind to bifrost (it calls Bedrock on behalf of agents)
resource "aws_eks_pod_identity_association" "bifrost" {
  cluster_name    = module.eks.cluster_name
  namespace       = "agents"
  service_account = "bifrost"
  role_arn        = aws_iam_role.agents.arn
}
