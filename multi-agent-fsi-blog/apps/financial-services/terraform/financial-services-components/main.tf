provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "cluster" {
  name = var.eks_cluster_name
}

# ============================================================================
# AgentCore Memory (advisor profile recall)
# ============================================================================

module "memory" {
  count  = var.enable_memory ? 1 : 0
  source = "../modules/memory"

  name                  = var.project_name
  description           = "Memory for ${var.project_name} financial advisor"
  event_expiry_duration = 30

  tags = {
    Name    = "${var.project_name}-memory"
    Project = var.project_name
  }
}

# ============================================================================
# AgentCore Browser (market-data live quotes)
# ============================================================================

module "browser" {
  count  = var.enable_browser ? 1 : 0
  source = "../modules/browser"

  name         = var.project_name
  description  = "Browser for ${var.project_name} market-data agent"
  network_mode = var.network_mode

  tags = {
    Name    = "${var.project_name}-browser"
    Project = var.project_name
  }
}

# ============================================================================
# AgentCore Code Interpreter (portfolio-analyst + risk-assessment)
# ============================================================================

module "code_interpreter" {
  count  = var.enable_code_interpreter ? 1 : 0
  source = "../modules/code-interpreter"

  name         = var.project_name
  description  = "Code Interpreter for ${var.project_name} analysis agents"
  network_mode = var.network_mode

  tags = {
    Name    = "${var.project_name}-code-interpreter"
    Project = var.project_name
  }
}

# ============================================================================
# Shared IAM Role (Pod Identity target for all 4 agents + MCP server)
# ============================================================================

resource "aws_iam_role" "financial_agent_role" {
  name = "${var.project_name}-agent-role"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession"
      ]
    }]
  })
}

resource "aws_iam_role_policy" "financial_agent_policy" {
  role = aws_iam_role.financial_agent_role.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeAgentCoreTool",
          "bedrock-agentcore:*"
        ]
        Resource = [
          "arn:aws:bedrock:${var.aws_region}:${data.aws_caller_identity.current.account_id}:agent-core-tool/*",
          "arn:aws:bedrock-agentcore:${var.aws_region}:${data.aws_caller_identity.current.account_id}:*"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "arn:aws:bedrock:*::foundation-model/*"
      },
      {
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream"
        ]
        Resource = "arn:aws:bedrock:*:${data.aws_caller_identity.current.account_id}:inference-profile/*"
      }
    ]
  })
}

# ============================================================================
# Pod Identity Associations (one per agent SA + MCP server SA)
# ============================================================================

resource "aws_eks_pod_identity_association" "agent_pod_identity" {
  for_each = toset(var.agent_service_accounts)

  cluster_name    = var.eks_cluster_name
  namespace       = var.namespace
  service_account = each.value
  role_arn        = aws_iam_role.financial_agent_role.arn
}
