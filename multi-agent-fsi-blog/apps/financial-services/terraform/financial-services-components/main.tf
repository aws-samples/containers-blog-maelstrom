provider "aws" {
  region = var.aws_region
}

data "aws_caller_identity" "current" {}

data "aws_eks_cluster" "cluster" {
  name = var.eks_cluster_name
}

# ============================================================================
# Per-agent AgentCore provisioning
#
# This module is instantiated once per agent by the Flux Terraform CRs
# rendered from apps/financial-services/gitops/.../templates/terraform-resource.yaml.
# Each invocation receives:
#   - project_name: per-agent (e.g. "financial-services-portfolio-analyst")
#     so AWS resource names don't collide.
#   - agent_sa: the single ServiceAccount name this agent's pod uses.
#   - enable_*: toggles for each AgentCore capability this agent opted into.
#
# The module creates:
#   - 0..3 AgentCore resources (Memory/Browser/CodeInterpreter) scoped to
#     this agent, gated by the enable_* flags.
#   - Exactly 1 IAM role (the agent's Pod Identity target).
#   - Exactly 1 Pod Identity association binding var.agent_sa to that role.
#
# Agents that don't need any AgentCore capability still get the IAM role
# and Pod Identity association so Bedrock model invocation works.
# ============================================================================

module "memory" {
  count  = var.enable_memory ? 1 : 0
  source = "../modules/memory"

  name                  = var.project_name
  description           = "Memory for ${var.project_name}"
  event_expiry_duration = 30

  tags = {
    Name    = "${var.project_name}-memory"
    Project = var.project_name
    Agent   = var.agent_sa
  }
}

module "browser" {
  count  = var.enable_browser ? 1 : 0
  source = "../modules/browser"

  name         = var.project_name
  description  = "Browser for ${var.project_name}"
  network_mode = var.network_mode

  tags = {
    Name    = "${var.project_name}-browser"
    Project = var.project_name
    Agent   = var.agent_sa
  }
}

module "code_interpreter" {
  count  = var.enable_code_interpreter ? 1 : 0
  source = "../modules/code-interpreter"

  name         = var.project_name
  description  = "Code Interpreter for ${var.project_name}"
  network_mode = var.network_mode

  tags = {
    Name    = "${var.project_name}-code-interpreter"
    Project = var.project_name
    Agent   = var.agent_sa
  }
}

# ============================================================================
# Per-agent IAM role (Pod Identity target)
#
# Named after the project_name so each agent gets its own role. Grants
# AgentCore tool invocation (scoped to anything under this account) and
# Bedrock model invocation. Fine-grained scoping to only the agent's own
# resources is a production follow-up — the blog's threat model is in-cluster
# workload isolation via Pod Identity + Gateway authz, not least-privilege
# IAM within a single agent's role.
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

  tags = {
    Project = var.project_name
    Agent   = var.agent_sa
  }
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
# Pod Identity Association (exactly one, for this agent's SA)
# ============================================================================

resource "aws_eks_pod_identity_association" "agent_pod_identity" {
  cluster_name    = var.eks_cluster_name
  namespace       = var.namespace
  service_account = var.agent_sa
  role_arn        = aws_iam_role.financial_agent_role.arn
}
