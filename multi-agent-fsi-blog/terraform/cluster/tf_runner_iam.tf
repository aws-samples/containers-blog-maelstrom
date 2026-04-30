# ----------------------------------------------------------------------------
# IAM role + Pod Identity association for the Tofu Controller runner pod.
#
# The Tofu Controller runs Terraform inside the cluster (via `tf-runner` SA in
# the flux-system namespace) to provision AgentCore Memory/Browser/Code
# Interpreter, IAM roles for agent pods, and Pod Identity associations for
# each agent SA. This role is what those in-cluster Terraform plans execute
# under.
#
# The SA itself is created by the tf-controller Helm chart when ArgoCD syncs
# `gitops/root/11-tofu-controller.yaml`. Pod Identity binds by namespace + SA
# name, so the association is safe to create before the SA exists.
# ----------------------------------------------------------------------------

locals {
  tf_runner_namespace = "flux-system"
  tf_runner_sa        = "tf-runner"
  tf_runner_role_name = "${var.cluster_name}-tf-runner"
}

resource "aws_iam_role" "tf_runner" {
  name = local.tf_runner_role_name

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "pods.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession",
      ]
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "tf_runner" {
  name = "${local.tf_runner_role_name}-policy"
  role = aws_iam_role.tf_runner.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # AgentCore resource lifecycle + Bedrock read-only lookups.
      {
        Sid      = "AgentCoreFullControl"
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:*"]
        Resource = "*"
      },
      {
        Sid    = "BedrockMetadata"
        Effect = "Allow"
        Action = [
          "bedrock:GetFoundationModel",
          "bedrock:ListFoundationModels",
          "bedrock:ListInferenceProfiles",
          "bedrock:GetInferenceProfile",
        ]
        Resource = "*"
      },
      # LiteLLM reuses this role (via Pod Identity in the litellm ns) to
      # actually call Bedrock models. Without Invoke* it can auth but every
      # completion returns 500 "not authorized to perform: bedrock:
      # InvokeModelWithResponseStream".
      {
        Sid    = "BedrockInvoke"
        Effect = "Allow"
        Action = [
          "bedrock:InvokeModel",
          "bedrock:InvokeModelWithResponseStream",
          "bedrock:Converse",
          "bedrock:ConverseStream",
        ]
        Resource = [
          "arn:aws:bedrock:*::foundation-model/*",
          "arn:aws:bedrock:*:*:inference-profile/*",
        ]
      },
      # IAM for creating the agent execution role + attaching inline policies.
      {
        Sid    = "IamForAgentRole"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:PassRole",
          "iam:TagRole",
          "iam:UntagRole",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies",
          "iam:UpdateAssumeRolePolicy",
        ]
        Resource = "*"
      },
      # Pod Identity associations for each agent + MCP server SA.
      {
        Sid    = "EksPodIdentity"
        Effect = "Allow"
        Action = [
          "eks:CreatePodIdentityAssociation",
          "eks:DeletePodIdentityAssociation",
          "eks:DescribePodIdentityAssociation",
          "eks:ListPodIdentityAssociations",
          "eks:UpdatePodIdentityAssociation",
          "eks:DescribeCluster",
        ]
        Resource = "*"
      },
      # VPC lookups used by Terraform data sources.
      {
        Sid    = "VpcLookups"
        Effect = "Allow"
        Action = [
          "ec2:DescribeVpcs",
          "ec2:DescribeSubnets",
          "ec2:DescribeSecurityGroups",
        ]
        Resource = "*"
      },
      # STS identity lookups (aws_caller_identity).
      {
        Sid      = "StsIdentity"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "tf_runner" {
  cluster_name    = module.eks.cluster_name
  namespace       = local.tf_runner_namespace
  service_account = local.tf_runner_sa
  role_arn        = aws_iam_role.tf_runner.arn

  tags = local.tags
}

# The tf-controller executes `terraform apply` inside a Pod that lives in the
# same namespace as the Terraform CR it's reconciling — not in flux-system.
# Every namespace hosting a Terraform CR therefore needs its own tf-runner
# ServiceAccount, and each needs a Pod Identity binding to the same IAM role.
resource "aws_eks_pod_identity_association" "tf_runner_financial_services" {
  cluster_name    = module.eks.cluster_name
  namespace       = "financial-services"
  service_account = local.tf_runner_sa
  role_arn        = aws_iam_role.tf_runner.arn

  tags = local.tags
}

# LiteLLM proxy calls Bedrock directly via boto3. Reuse the same IAM role
# so it can InvokeModel on foundation models and inference profiles. For a
# production cluster you'd scope this to a dedicated LiteLLM role limited to
# the model subset the proxy is allowed to route to.
resource "aws_eks_pod_identity_association" "litellm" {
  cluster_name    = module.eks.cluster_name
  namespace       = "litellm"
  service_account = "litellm"
  role_arn        = aws_iam_role.tf_runner.arn

  tags = local.tags
}
