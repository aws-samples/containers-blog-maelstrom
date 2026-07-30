# ----------------------------------------------------------------------------
# ACK + kro EKS Capabilities and their IAM roles.
#
# AWS Controllers for Kubernetes (ACK) and kro (Kube Resource Orchestrator)
# are installed as AWS-managed EKS Capabilities (aws_eks_capability). AWS runs
# the controllers in the cluster; we only supply the IAM role each capability
# assumes and let the capability install its CRDs + controller Deployments.
#
# Two capabilities:
#   - ACK  : installs the service controllers (bedrockagentcorecontrol, iam,
#            eks, …). All ACK controllers assume the ack_capability role below.
#            The managed build now reconciles the Browser kind, so we no longer
#            self-manage the controllers via ArgoCD.
#   - KRO  : installs kro, which reconciles the ResourceGraphDefinitions in
#            gitops/addons/agentcore-rgds/. kro creates only in-cluster CRs
#            (the ACK resources the RGDs template), so it needs no AWS perms.
#
# Capability roles trust capabilities.eks.amazonaws.com (NOT
# pods.eks.amazonaws.com — that was the Crossplane / self-managed Pod Identity
# model). The permission set on the ACK role is the same one the Crossplane
# provider role used: AgentCore + Bedrock + IAM (per-agent execution roles) +
# EKS Pod Identity + STS.
# ----------------------------------------------------------------------------

locals {
  ack_capability_role  = "${var.cluster_name}-ack-capability"
  kro_capability_role  = "${var.cluster_name}-kro-capability"
  litellm_bedrock_role = "${var.cluster_name}-litellm-bedrock"
}

# --- ACK capability role ----------------------------------------------------
resource "aws_iam_role" "ack_capability" {
  name = local.ack_capability_role

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "capabilities.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession",
      ]
    }]
  })

  tags = local.tags
}

resource "aws_iam_role_policy" "ack_capability" {
  name = "${local.ack_capability_role}-policy"
  role = aws_iam_role.ack_capability.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      # AgentCore resource lifecycle — the ACK bedrockagentcorecontrol
      # controller calls these for every Memory / Browser / CodeInterpreter
      # CR the financial-services chart renders (via the kro RGDs).
      {
        Sid      = "AgentCoreFullControl"
        Effect   = "Allow"
        Action   = ["bedrock-agentcore:*"]
        Resource = "*"
      },
      # Bedrock metadata the AgentCore controller needs at reconcile time.
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
      # IAM — the ACK iam controller creates/deletes per-agent execution
      # roles and manages their inline policies.
      {
        Sid    = "IamForAgentRole"
        Effect = "Allow"
        Action = [
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:GetRole",
          "iam:UpdateRole",
          "iam:PassRole",
          "iam:TagRole",
          "iam:UntagRole",
          # The ACK iam controller reads a role's tags on every reconcile;
          # without ListRoleTags the Role never reaches ResourceSynced=True,
          # which in turn blocks PodIdentityAssociation roleRef resolution.
          "iam:ListRoleTags",
          "iam:AttachRolePolicy",
          "iam:DetachRolePolicy",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:GetRolePolicy",
          "iam:ListAttachedRolePolicies",
          "iam:ListRolePolicies",
          "iam:UpdateAssumeRolePolicy",
          # ACK Policy resources (standalone managed policies) — kept for
          # parity with the kro pod-identity pattern that attaches a Policy.
          "iam:CreatePolicy",
          "iam:DeletePolicy",
          "iam:GetPolicy",
          "iam:GetPolicyVersion",
          "iam:ListPolicyVersions",
          "iam:CreatePolicyVersion",
          "iam:DeletePolicyVersion",
        ]
        Resource = "*"
      },
      # Pod Identity — the ACK eks controller creates/deletes
      # PodIdentityAssociation CRs binding each agent SA to its role.
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
          "eks:TagResource",
          "eks:UntagResource",
          "eks:ListTagsForResource",
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

# --- kro capability role ----------------------------------------------------
# kro only creates in-cluster CRs (the ACK resources its RGDs template); it
# makes no direct AWS calls, so the role carries no AWS permissions. The role
# still has to exist and trust the capability service principal.
resource "aws_iam_role" "kro_capability" {
  name = local.kro_capability_role

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Principal = {
        Service = "capabilities.eks.amazonaws.com"
      }
      Action = [
        "sts:AssumeRole",
        "sts:TagSession",
      ]
    }]
  })

  tags = local.tags
}

# --- Capabilities -----------------------------------------------------------
# The ACK capability installs the service controllers + their CRDs. The kro
# capability installs kro + the ResourceGraphDefinition CRD. bootstrap.sh
# waits for both to reach ACTIVE before the financial-services chart's ACK
# CRs / composite claims can reconcile. aws_eks_capability has no version
# argument — AWS controls the build (the current managed build reconciles the
# Browser kind).
resource "aws_eks_capability" "ack" {
  cluster_name              = module.eks.cluster_name
  capability_name           = "ack"
  type                      = "ACK"
  role_arn                  = aws_iam_role.ack_capability.arn
  delete_propagation_policy = "RETAIN"

  tags = local.tags
}

resource "aws_eks_capability" "kro" {
  cluster_name              = module.eks.cluster_name
  capability_name           = "kro"
  type                      = "KRO"
  role_arn                  = aws_iam_role.kro_capability.arn
  delete_propagation_policy = "RETAIN"

  tags = local.tags
}

# ----------------------------------------------------------------------------
# LiteLLM Bedrock role.
#
# LiteLLM calls Bedrock directly via boto3. Previously it reused the Crossplane
# provider role; that role is gone, so it gets a dedicated least-privilege role
# scoped to model invocation + metadata, bound via Pod Identity. Trust here IS
# pods.eks.amazonaws.com — this is a workload Pod Identity, not a capability.
# ----------------------------------------------------------------------------
resource "aws_iam_role" "litellm_bedrock" {
  name = local.litellm_bedrock_role

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

resource "aws_iam_role_policy" "litellm_bedrock" {
  name = "${local.litellm_bedrock_role}-policy"
  role = aws_iam_role.litellm_bedrock.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
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
    ]
  })
}

resource "aws_eks_pod_identity_association" "litellm" {
  cluster_name    = module.eks.cluster_name
  namespace       = "litellm"
  service_account = "litellm"
  role_arn        = aws_iam_role.litellm_bedrock.arn

  tags = local.tags
}
