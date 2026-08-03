# ACK controller and ADOT are installed via Helm in the bootstrap module
# (they require the cluster to be fully ready + cert-manager for ADOT)

# IAM role for ACK controllers (Pod Identity)
resource "aws_iam_role" "ack_capability" {
  name = "${var.cluster_name}-ack-capability"

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

resource "aws_iam_role_policy" "ack_capability" {
  name = "ack-agentcore-policy"
  role = aws_iam_role.ack_capability.id

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "bedrock:*",
          "bedrockagentcore:*",
          "iam:CreateRole",
          "iam:DeleteRole",
          "iam:UpdateRole",
          "iam:GetRole",
          "iam:PutRolePolicy",
          "iam:DeleteRolePolicy",
          "iam:ListRoleTags",
          "iam:TagRole",
          "eks:CreatePodIdentityAssociation",
          "eks:DeletePodIdentityAssociation",
          "eks:DescribePodIdentityAssociation",
          "eks:ListPodIdentityAssociations"
        ]
        Resource = "*"
      }
    ]
  })
}

# IAM role for kro (installed via Helm in bootstrap)
resource "aws_iam_role" "kro_capability" {
  name = "${var.cluster_name}-kro"

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
