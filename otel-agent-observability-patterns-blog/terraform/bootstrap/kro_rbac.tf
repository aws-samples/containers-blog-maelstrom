# Grant kro RBAC over *.services.k8s.aws CRDs
resource "kubernetes_cluster_role" "kro_ack_access" {
  metadata {
    name = "kro-ack-resource-access"
  }

  rule {
    api_groups = [
      "bedrockagentcorecontrol.services.k8s.aws",
      "iam.services.k8s.aws",
      "eks.services.k8s.aws"
    ]
    resources = ["*"]
    verbs     = ["*"]
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
    kind      = "User"
    name      = var.kro_role_arn
    api_group = "rbac.authorization.k8s.io"
  }
}
