terraform {
  required_version = ">= 1.5"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.100"
    }
  }
}

provider "aws" {
  region = var.region
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  azs = slice(data.aws_availability_zones.available.names, 0, 3)
}

# ----------------------------------------------------------------------------
# VPC (3 AZs, private + public subnets, tagged for EKS LB discovery)
# ----------------------------------------------------------------------------
module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = "${var.cluster_name}-vpc"
  cidr = "10.0.0.0/16"

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet("10.0.0.0/16", 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet("10.0.0.0/16", 8, k + 48)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  public_subnet_tags = {
    "kubernetes.io/role/elb" = 1
  }

  private_subnet_tags = {
    "kubernetes.io/role/internal-elb" = 1
  }

  tags = var.tags
}

# ----------------------------------------------------------------------------
# EKS Auto Mode cluster
#   - Auto Mode provides compute (managed NodePools), EBS CSI, VPC CNI,
#     kube-proxy, CoreDNS, AWS Load Balancer Controller, AND Pod Identity.
#   - node_pools = ["system", "general-purpose"] creates the default pools.
# ----------------------------------------------------------------------------
module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "~> 20.31"

  cluster_name    = var.cluster_name
  cluster_version = var.eks_version

  # Auto Mode with default node pools
  cluster_compute_config = {
    enabled    = true
    node_pools = ["system", "general-purpose"]
  }

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_public_access = true

  # Grant the Terraform caller cluster-admin so bootstrap can install Helm charts
  enable_cluster_creator_admin_permissions = true

  tags = var.tags
}
