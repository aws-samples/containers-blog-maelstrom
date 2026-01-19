# KEDA Operator

resource "helm_release" "keda" {
  name             = "keda"
  repository       = "https://kedacore.github.io/charts"
  chart            = "keda"
  namespace        = "kube-system"
  version          = "2.18.1"
  replace          = true
  cleanup_on_fail  = true
  wait             = true

  values = [yamlencode({
    ## Global tolerations and nodeSelector for all KEDA pods
    tolerations = [{
      key    = "CriticalAddonsOnly"
      operator = "Exists"
    }]
    nodeSelector = {
      "karpenter.sh/nodepool" = "system"
    }
    
    prometheus = {
      operator = {
        enabled = true
        serviceMonitor = {
          enabled = true
          additionalLabels = {
            release = "kube-prometheus-stack"
          }
        }
      }
      metricServer = {
        enabled = true
        serviceMonitor = {
          enabled = true
          additionalLabels = {
            release = "kube-prometheus-stack"
          }
        }
      }
    }
  })]

  depends_on = [module.eks, module.keda_pod_identity, resource.helm_release.kube_prometheus_stack]
}

# Pod Identity for KEDA operator

module "keda_pod_identity" {
  source = "terraform-aws-modules/eks-pod-identity/aws"

  name = "${local.name}-keda"

  additional_policy_arns = {
    keda_msk = aws_iam_policy.keda_msk_policy.arn
  }

  associations = {
    keda = {
      cluster_name    = module.eks.cluster_name
      namespace       = "kube-system"
      service_account = "keda-operator"
    }
  }

  tags = local.tags
}

# Kube Prometheus Stack

resource "helm_release" "kube_prometheus_stack" {
  name             = "kube-prometheus-stack"
  repository       = "https://prometheus-community.github.io/helm-charts"
  chart            = "kube-prometheus-stack"
  namespace        = "kube-system"
  version          = "65.1.1"
  replace          = true
  cleanup_on_fail  = true
  wait             = true

  values = [yamlencode({
    prometheusOperator = {
      tolerations = [{
        key    = "CriticalAddonsOnly"
        operator = "Exists"
      }]
      nodeSelector = {
        "karpenter.sh/nodepool" = "system"
      }
    }
    prometheus = {
      prometheusSpec = {
        tolerations = [{
          key    = "CriticalAddonsOnly"
          operator = "Exists"
        }]
        nodeSelector = {
          "karpenter.sh/nodepool" = "system"
        }
        storageSpec = {
          volumeClaimTemplate = {
            spec = {
              accessModes = ["ReadWriteOnce"]
              resources = {
                requests = {
                  storage = "50Gi"
                }
              }
            }
          }
        }
      }
    }
    alertmanager = {
      alertmanagerSpec = {
        tolerations = [{
          key    = "CriticalAddonsOnly"
          operator = "Exists"
        }]
        nodeSelector = {
          "karpenter.sh/nodepool" = "system"
        }
      }
    }
    grafana = {
      tolerations = [{
        key    = "CriticalAddonsOnly"
        operator = "Exists"
      }]
      nodeSelector = {
        "karpenter.sh/nodepool" = "system"
      }
    }
    "kube-state-metrics" = {
      tolerations = [{
        key    = "CriticalAddonsOnly"
        operator = "Exists"
      }]
      nodeSelector = {
        "karpenter.sh/nodepool" = "system"
      }
    }
    "prometheus-node-exporter" = {
      tolerations = [{
        key    = "CriticalAddonsOnly"
        operator = "Exists"
      }]
      nodeSelector = {
        "karpenter.sh/nodepool" = "system"
      }
    }
  })]

  depends_on = [module.eks]
}

# Apply all K8s manifests

locals {
  msk_brokers = split(",", replace(module.msk_cluster.bootstrap_brokers_sasl_iam, ":9098", ""))
  k8s_yaml_files = fileset("${path.module}/K8s-yaml", "*.yaml")
  k8s_yaml_templates = fileset("${path.module}/K8s-yaml", "*.yaml.tpl")
}

resource "kubectl_manifest" "k8s_yamls" {
  for_each = local.k8s_yaml_files
  
  yaml_body = file("${path.module}/K8s-yaml/${each.value}")
  wait      = false

  depends_on = [module.eks]
}

resource "kubectl_manifest" "k8s_templates" {
  for_each = local.k8s_yaml_templates
  
  yaml_body = templatefile("${path.module}/K8s-yaml/${each.value}", {
    brokers = local.msk_brokers
  })
  wait      = false

  depends_on = [helm_release.kube_prometheus_stack]
}
