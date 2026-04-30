terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.70"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = "~> 2.30"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Project = var.cluster_name
    Blog    = "finops-agents-on-eks-auto-mode"
  }
}

# ----------------------------------------------------------------------------
# VPC (3 AZs, private + public subnets, tagged for EKS LB discovery)
# ----------------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.13"

  name = "${var.cluster_name}-vpc"
  cidr = var.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(var.vpc_cidr, 8, k + 48)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }
  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = local.tags
}

# ----------------------------------------------------------------------------
# EKS Auto Mode cluster
#   - Auto Mode provides compute (managed NodePools), EBS CSI, VPC CNI,
#     kube-proxy, CoreDNS, and the AWS Load Balancer Controller out of the box.
#   - We only add the Pod Identity agent addon so workloads can assume IAM
#     roles without IRSA wiring.
# ----------------------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = var.cluster_name
  cluster_version = var.cluster_version

  # Auto Mode
  cluster_compute_config = {
    enabled    = true
    node_pools = ["system", "general-purpose"]
  }

  vpc_id                   = module.vpc.vpc_id
  subnet_ids               = module.vpc.private_subnets
  control_plane_subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  # Give the Terraform caller cluster-admin so we can Helm-install ArgoCD
  # from the bootstrap stack.
  enable_cluster_creator_admin_permissions = true

  cluster_addons = {
    eks-pod-identity-agent = {
      most_recent = true
    }
  }

  tags = local.tags
}
