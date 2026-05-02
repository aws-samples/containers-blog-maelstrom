# ----------------------------------------------------------------------------
# IAM role + Pod Identity association for the Crossplane AWS providers.
#
# Each Upbound Provider (aws-bedrockagentcore, aws-iam, aws-eks) runs its
# own controller Deployment in crossplane-system. They all share one
# ServiceAccount (crossplane-aws-provider-sa) via the DeploymentRuntimeConfig
# in gitops/addons/crossplane-providers/01-deployment-runtime-config.yaml.
# Pod Identity binds that SA to the IAM role below.
#
# Scope: every AWS API call Crossplane makes on our behalf runs under this
# role. That covers:
#   - AgentCore Memory/Browser/Code Interpreter lifecycle
#   - IAM Role + RolePolicy lifecycle (for per-agent execution roles)
#   - EKS PodIdentityAssociation lifecycle (binding agent SAs to those roles)
#   - Bedrock model invocation (reused by LiteLLM — see the litellm PIA below)
#
# Pod Identity binds by namespace + SA name, so the association is safe to
# create before Crossplane and its providers roll out.
# ----------------------------------------------------------------------------

locals {
  crossplane_namespace     = "crossplane-system"
  crossplane_provider_sa   = "crossplane-aws-provider-sa"
  crossplane_provider_role = "${var.cluster_name}-crossplane-aws-provider"
}

resource "aws_iam_role" "crossplane_provider" {
  name = local.crossplane_provider_role

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

resource "aws_iam_role_policy" "crossplane_provider" {
  name = "${local.crossplane_provider_role}-policy"
  role = aws_iam_role.crossplane_provider.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # AgentCore resource lifecycle — Crossplane's
      # provider-aws-bedrockagentcore calls these for every Memory /
      # Browser / CodeInterpreter MR in the financial-services chart.
      {
        Sid      = "AgentCoreFullControl"
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:*"]
        Resource = "*"
      },
      # Bedrock metadata the AgentCore provider needs at plan time.
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
      # LiteLLM reuses this role via its own Pod Identity association
      # (below) to actually call Bedrock models. Without Invoke* every
      # completion 500s with "not authorized to perform: bedrock:
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
      # IAM — Crossplane's provider-aws-iam creates/deletes per-agent
      # execution roles and attaches inline policies.
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
      # Pod Identity — Crossplane's provider-aws-eks creates/deletes
      # PodIdentityAssociation MRs binding each agent SA to its role.
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
      # STS identity lookups.
      {
        Sid      = "StsIdentity"
        Effect   = "Allow"
        Action   = ["sts:GetCallerIdentity"]
        Resource = "*"
      },
    ]
  })
}

resource "aws_eks_pod_identity_association" "crossplane_provider" {
  cluster_name    = module.eks.cluster_name
  namespace       = local.crossplane_namespace
  service_account = local.crossplane_provider_sa
  role_arn        = aws_iam_role.crossplane_provider.arn

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
  role_arn        = aws_iam_role.crossplane_provider.arn

  tags = local.tags
}
