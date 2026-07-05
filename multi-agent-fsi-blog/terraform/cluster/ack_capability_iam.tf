# ----------------------------------------------------------------------------
# ACK controllers (self-managed via ArgoCD) + kro EKS Capability + IAM roles.
#
# kro (Kube Resource Orchestrator) is installed as an AWS-managed EKS
# Capability (aws_eks_capability): it reconciles the ResourceGraphDefinitions
# in gitops/addons/agentcore-rgds/ and creates only in-cluster CRs, so it
# needs no AWS permissions.
#
# AWS Controllers for Kubernetes (ACK) are NOT installed via the managed
# Capability: that build ships an older bedrockagentcorecontrol controller that
# does not reconcile the Browser kind. Instead the ACK service controllers
# (bedrockagentcorecontrol, iam, eks) are self-managed via ArgoCD
# (gitops/root/templates/09-ack-controllers.yaml), pulling the published
# controller charts from public ECR. They run in the ack-system namespace and
# share one IAM role, bound to each controller ServiceAccount via EKS Pod
# Identity. The permission set matches what the previous Crossplane provider
# role used: AgentCore + Bedrock + IAM (per-agent execution roles) + EKS Pod
# Identity + STS.
# ----------------------------------------------------------------------------

locals {
  ack_controller_role  = "${var.cluster_name}-ack-controller"
  kro_capability_role  = "${var.cluster_name}-kro-capability"
  litellm_bedrock_role = "${var.cluster_name}-litellm-bedrock"

  # ACK controller ServiceAccounts (chart default names) in ack-system, each
  # bound to the shared ACK controller role via Pod Identity.
  ack_controller_service_accounts = [
    "ack-bedrockagentcorecontrol-controller",
    "ack-iam-controller",
    "ack-eks-controller",
  ]
}

# --- ACK controller role (self-managed controllers, Pod Identity) -----------
resource "aws_iam_role" "ack_controller" {
  name = local.ack_controller_role

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

resource "aws_iam_role_policy" "ack_controller" {
  name = "${local.ack_controller_role}-policy"
  role = aws_iam_role.ack_controller.id

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

# --- kro Capability ---------------------------------------------------------
# Installs kro + the ResourceGraphDefinition CRD. bootstrap.sh waits for it to
# reach ACTIVE before the AgentCore RGDs reconcile. (ACK is self-managed via
# ArgoCD — see 09-ack-controllers.yaml — not installed as a Capability.)
resource "aws_eks_capability" "kro" {
  cluster_name              = module.eks.cluster_name
  capability_name           = "kro"
  type                      = "KRO"
  role_arn                  = aws_iam_role.kro_capability.arn
  delete_propagation_policy = "RETAIN"

  tags = local.tags
}

# --- ACK controller Pod Identity associations -------------------------------
# Bind each self-managed ACK controller ServiceAccount (created by its Helm
# chart in ack-system) to the shared ACK controller role. Pod Identity binds by
# namespace + SA name, so these are safe to create before the controllers roll
# out via ArgoCD.
resource "aws_eks_pod_identity_association" "ack_controllers" {
  for_each = toset(local.ack_controller_service_accounts)

  cluster_name    = module.eks.cluster_name
  namespace       = "ack-system"
  service_account = each.value
  role_arn        = aws_iam_role.ack_controller.arn

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
