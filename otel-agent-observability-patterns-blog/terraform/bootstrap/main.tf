terraform {
  required_version = ">= 1.5"

  required_providers {
    aws        = { source = "hashicorp/aws", version = ">= 5.60.0" }
    kubernetes = { source = "hashicorp/kubernetes", version = "~> 2.30" }
    helm       = { source = "hashicorp/helm", version = "~> 2.13" }
  }
}

provider "aws" {
  region = var.region
}

data "aws_eks_cluster" "this" {
  name = var.cluster_name
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.this.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
  }
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.this.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.this.certificate_authority[0].data)

    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args        = ["eks", "get-token", "--cluster-name", var.cluster_name, "--region", var.region]
    }
  }
}

# Install ArgoCD
resource "helm_release" "argocd" {
  name             = "argocd"
  repository       = "https://argoproj.github.io/argo-helm"
  chart            = "argo-cd"
  version          = "10.3.3"
  namespace        = "argocd"
  create_namespace = true
  timeout          = 600
  wait             = false  # Auto Mode nodes may take time to provision

  set {
    name  = "server.service.type"
    value = "ClusterIP"
  }

  set {
    name  = "configs.params.server\\.insecure"
    value = "true"
  }

  # Pin Redis to a patched, open-source image. Avoid 7.4.0 <= v < 8.0.0
  # (non-OSS license range) and older alpine bases carrying openssl/zlib/musl CVEs.
  set {
    name  = "redis.image.repository"
    value = "public.ecr.aws/docker/library/redis"
  }

  # 8.6.6-alpine rebuilds on alpine-minirootfs-3.23.5, which ships
  # openssl 3.5.8-r0 — fixing CVE-2026-14456, CVE-2026-14457, CVE-2026-18798
  # (High) present in the openssl 3.5.7-r0 base of the earlier 8.6.4-alpine build.
  set {
    name  = "redis.image.tag"
    value = "8.6.6-alpine"
  }
}

# Install kro (Kube Resource Orchestrator)
resource "helm_release" "kro" {
  name             = "kro"
  repository       = "oci://public.ecr.aws/kro"
  chart            = "kro"
  version          = "0.1.0"
  namespace        = "kro"
  create_namespace = true
  timeout          = 600
  wait             = false
}

# Default gp3 StorageClass — EKS Auto Mode only creates gp2 (not default).
resource "kubernetes_storage_class" "gp3_default" {
  metadata {
    name = "gp3"
    annotations = {
      "storageclass.kubernetes.io/is-default-class" = "true"
    }
  }

  storage_provisioner    = "ebs.csi.eks.amazonaws.com"
  volume_binding_mode    = "WaitForFirstConsumer"
  reclaim_policy         = "Delete"
  allow_volume_expansion = true

  parameters = {
    type   = "gp3"
    fsType = "ext4"
  }
}
