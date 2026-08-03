# ADOT is installed as a managed add-on in the bootstrap module (after cert-manager).
# IAM role is created here so it's available as a Terraform output.

resource "aws_iam_role" "adot" {
  name = "${var.cluster_name}-adot"

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

resource "aws_iam_role_policy_attachment" "adot_cloudwatch" {
  role       = aws_iam_role.adot.name
  policy_arn = "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy"
}

resource "aws_iam_role_policy_attachment" "adot_xray" {
  role       = aws_iam_role.adot.name
  policy_arn = "arn:aws:iam::aws:policy/AWSXRayDaemonWriteAccess"
}

# Pod Identity for the ADOT DaemonSet collector
resource "aws_eks_pod_identity_association" "adot_collector" {
  cluster_name    = module.eks.cluster_name
  namespace       = "opentelemetry-operator-system"
  service_account = "adot-collector"
  role_arn        = aws_iam_role.adot.arn
}
