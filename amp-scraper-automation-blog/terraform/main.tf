terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {}

### variables ###
variable "eks_cluster_name" {}

# prometheus_workspace_id is not required
variable "prometheus_workspace_id" {
  default = ""
}

variable "project" {
  default = "amp-scraper-automation"
}

variable "tags" {
  default = {
    "Project" : "amp-scraper-automation"
    "Source" : "Terraform"
  }
}

### data - read only resources ###
data "aws_eks_cluster" "this" {
  name = var.eks_cluster_name
}

data "aws_prometheus_workspace" "this" {
  workspace_id = local.workspace_id
}
# These helpers solve the ValidationException error thrown by the scraper if
# eks subnets are not in unique availability zones.
data "aws_subnet" "helper" {
  for_each = toset(data.aws_eks_cluster.this.vpc_config[0].subnet_ids)
  id       = each.key
}

### locals - custom logic ###
locals {
  # use provided workspace otherwise create new
  workspace_id  = var.prometheus_workspace_id == "" ? aws_prometheus_workspace.this[0].id : var.prometheus_workspace_id
  workspace_arn = var.prometheus_workspace_id == "" ? aws_prometheus_workspace.this[0].arn : data.aws_prometheus_workspace.this.arn

  # build a map of availability zone names to subnet Ids
  eks_availability_zone_subnets = {
    for subnet in data.aws_subnet.helper : subnet.availability_zone => subnet.id...
  }
}

### resources ###
resource "aws_prometheus_workspace" "this" {
  # use provided workspace otherwise create new
  count = var.prometheus_workspace_id == "" ? 1 : 0

  alias = var.project
  
  tags = merge(var.tags, {
    AMPAgentlessScraper = ""
  })
}

resource "aws_prometheus_scraper" "this" {
  alias = var.project

  source {
    eks {
      cluster_arn = data.aws_eks_cluster.this.arn
      # taking one subnet id per availability zone to avoid validation error
      subnet_ids = [for subnet_ids in local.eks_availability_zone_subnets : subnet_ids[0]]
    }
  }

  scrape_configuration = <<EOT
global:
  scrape_interval: 30s
scrape_configs:
  # pod metrics
  - job_name: pod_exporter
    kubernetes_sd_configs:
      - role: pod
  # container metrics
  - job_name: cadvisor
    scheme: https
    authorization:
      credentials_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    kubernetes_sd_configs:
      - role: node
    relabel_configs:
      - action: labelmap
        regex: __meta_kubernetes_node_label_(.+)
      - replacement: kubernetes.default.svc:443
        target_label: __address__
      - source_labels: [__meta_kubernetes_node_name]
        regex: (.+)
        target_label: __metrics_path__
        replacement: /api/v1/nodes/$1/proxy/metrics/cadvisor
  # apiserver metrics
  - bearer_token_file: /var/run/secrets/kubernetes.io/serviceaccount/token
    job_name: kubernetes-apiservers
    kubernetes_sd_configs:
    - role: endpoints
    relabel_configs:
    - action: keep
      regex: default;kubernetes;https
      source_labels:
      - __meta_kubernetes_namespace
      - __meta_kubernetes_service_name
      - __meta_kubernetes_endpoint_port_name
    scheme: https
  # kube proxy metrics
  - job_name: kube-proxy
    honor_labels: true
    kubernetes_sd_configs:
    - role: pod
    relabel_configs:
    - action: keep
      source_labels:
      - __meta_kubernetes_namespace
      - __meta_kubernetes_pod_name
      separator: '/'
      regex: 'kube-system/kube-proxy.+'
    - source_labels:
      - __address__
      action: replace
      target_label: __address__
      regex: (.+?)(\\:\\d+)?
      replacement: $1:10249
EOT

  destination {
    amp {
      workspace_arn = local.workspace_arn
    }
  }
}