# ----------------------------------------------------------------------------
# RBAC for the kro EKS Capability to manage ACK resources.
#
# The AWS-managed kro Capability reconciles our ResourceGraphDefinitions and,
# in doing so, creates the ACK resources each RGD templates (Memory /
# CodeInterpreter / Role / PodIdentityAssociation). kro acts under its
# capability role's access-entry identity, which by default has NO Kubernetes
# RBAC over the *.services.k8s.aws CRDs — so those child creates are forbidden
# until we grant them here.
#
# The access-entry username for a capability role is the assumed-role ARN with
# the live session name. Bind the ClusterRole to that exact username.
# ----------------------------------------------------------------------------

data "aws_caller_identity" "current" {}

locals {
  kro_capability_role_arn_user = "arn:aws:sts::${data.aws_caller_identity.current.account_id}:assumed-role/${var.cluster_name}-kro-capability/KRO"
}

resource "kubernetes_cluster_role" "kro_ack_access" {
  metadata {
    name = "kro-ack-resource-access"
  }

  rule {
    api_groups = [
      "bedrockagentcorecontrol.services.k8s.aws",
      "iam.services.k8s.aws",
      "eks.services.k8s.aws",
      "services.k8s.aws",
    ]
    resources = ["*"]
    verbs     = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }

  rule {
    api_groups = [""]
    resources  = ["secrets"]
    verbs      = ["get", "list", "watch", "create", "update", "patch", "delete"]
  }
}

resource "kubernetes_cluster_role_binding" "kro_ack_access" {
  metadata {
    name = "kro-ack-resource-access"
  }

  role_ref {
    api_group = "rbac.authorization.k8s.io"
    kind      = "ClusterRole"
    name      = kubernetes_cluster_role.kro_ack_access.metadata[0].name
  }

  subject {
    api_group = "rbac.authorization.k8s.io"
    kind      = "User"
    name      = local.kro_capability_role_arn_user
  }
}
