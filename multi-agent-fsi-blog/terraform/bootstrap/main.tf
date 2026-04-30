terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    helm = {
      source  = "hashicorp/helm"
      version = "~> 2.15"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = "~> 2.1"
    }
    http = {
      source  = "hashicorp/http"
      version = "~> 3.4"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_eks_cluster" "cluster" {
  name = var.cluster_name
}

data "aws_eks_cluster_auth" "cluster" {
  name = var.cluster_name
}

# ----------------------------------------------------------------------------
# EKS OIDC issuer + JWKS — used by Agent Gateway to validate ServiceAccount
# tokens. The issuer URL is cluster-specific (set at creation time). The JWKS
# is a public static document at <issuer>/keys. Both are captured at bootstrap
# time and plumbed into the platform-root ArgoCD Application so child charts
# (specifically the financial-services AgentgatewayPolicy for jwtAuthentication)
# can render without any manual edits.
# ----------------------------------------------------------------------------
locals {
  oidc_issuer = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

data "http" "eks_jwks" {
  url = "${local.oidc_issuer}/keys"

  request_headers = {
    Accept = "application/json"
  }
}

provider "kubernetes" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
}

provider "helm" {
  kubernetes {
    host                   = data.aws_eks_cluster.cluster.endpoint
    cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
    token                  = data.aws_eks_cluster_auth.cluster.token
  }
}

provider "kubectl" {
  host                   = data.aws_eks_cluster.cluster.endpoint
  cluster_ca_certificate = base64decode(data.aws_eks_cluster.cluster.certificate_authority[0].data)
  token                  = data.aws_eks_cluster_auth.cluster.token
  load_config_file       = false
}

# ----------------------------------------------------------------------------
# ArgoCD install via the official Helm chart.
# ----------------------------------------------------------------------------
resource "kubernetes_namespace" "argocd" {
  metadata {
    name = "argocd"
  }
}

resource "helm_release" "argocd" {
  name       = "argocd"
  repository = "https://argoproj.github.io/argo-helm"
  chart      = "argo-cd"
  version    = var.argocd_chart_version
  namespace  = kubernetes_namespace.argocd.metadata[0].name

  values = [
    yamlencode({
      global = {
        domain = var.argocd_domain
      }
      server = {
        service = {
          type = "ClusterIP"
        }
        extraArgs = ["--insecure"]
      }
      configs = {
        params = {
          "server.insecure" = true
        }
        # Custom health check for Flux Terraform CR. Without this ArgoCD
        # marks the Terraform resource Healthy the instant the manifest is
        # accepted by the API server, so sync-wave 0 "completes" before
        # Tofu Controller has actually run `terraform apply`. Downstream
        # waves (MCP server, agents) then pull the outputs Secret that
        # doesn't exist yet and pods start with empty env vars.
        # Gate on the Ready condition instead.
        cm = {
          "resource.customizations.health.infra.contrib.fluxcd.io_Terraform" = <<-EOT
            hs = {}
            if obj.status ~= nil and obj.status.conditions ~= nil then
              for i, c in ipairs(obj.status.conditions) do
                if c.type == "Ready" then
                  if c.status == "True" then
                    hs.status = "Healthy"
                    hs.message = c.message
                    return hs
                  elseif c.status == "False" then
                    hs.status = "Degraded"
                    hs.message = c.message
                    return hs
                  end
                end
              end
            end
            hs.status = "Progressing"
            hs.message = "Waiting for Terraform Ready condition"
            return hs
          EOT
        }
      }
      dex = {
        enabled = false
      }
      notifications = {
        enabled = false
      }
      applicationSet = {
        enabled = true
      }
    }),
  ]
}

# ----------------------------------------------------------------------------
# Root ArgoCD Application (app-of-apps). Points at gitops/root which owns one
# Application per addon (see multi-agent-fsi-blog/gitops/root/).
# ----------------------------------------------------------------------------
resource "kubectl_manifest" "root_app" {
  depends_on = [helm_release.argocd]

  yaml_body = yamlencode({
    apiVersion = "argoproj.io/v1alpha1"
    kind       = "Application"
    metadata = {
      name      = "platform-root"
      namespace = "argocd"
      finalizers = [
        "resources-finalizer.argocd.argoproj.io",
      ]
    }
    spec = {
      project = "default"
      source = {
        repoURL        = var.gitops_repo_url
        targetRevision = var.gitops_repo_branch
        path           = var.gitops_root_path
        helm = {
          valueFiles = ["values.yaml"]
          parameters = [
            {
              name  = "gitOpsRepo.url"
              value = var.gitops_repo_url
            },
            {
              name  = "gitOpsRepo.branch"
              value = var.gitops_repo_branch
            },
            {
              name  = "eks.oidcIssuer"
              value = local.oidc_issuer
            },
            {
              name        = "eks.jwksJson"
              value       = data.http.eks_jwks.response_body
              forceString = true
            },
          ]
        }
      }
      destination = {
        server    = "https://kubernetes.default.svc"
        namespace = "argocd"
      }
      syncPolicy = {
        automated = {
          prune    = true
          selfHeal = true
        }
        syncOptions = [
          "CreateNamespace=true",
          "ServerSideApply=true",
        ]
        retry = {
          limit = 5
          backoff = {
            duration    = "10s"
            factor      = 2
            maxDuration = "5m"
          }
        }
      }
    }
  })
}
