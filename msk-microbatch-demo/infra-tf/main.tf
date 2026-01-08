terraform {
  required_version = ">= 1.3"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 6.2.0"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.9"
    }
    kubectl = {
      source  = "alekc/kubectl"
      version = ">= 2.1"
    }
  }
}

provider "aws" {
  region = local.region
}

provider "helm" {
  kubernetes = {
    host                   = module.eks.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)

    exec = {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name,
      "--region", local.region]
    }
  }
}

provider "kubectl" {
  apply_retry_count      = 5
  host                   = module.eks.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks.cluster_certificate_authority_data)
  load_config_file       = false

  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks.cluster_name,
    "--region", local.region]
  }
}

data "aws_availability_zones" "available" {
  # Do not include local zones
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

data "aws_region" "current" {}
data "aws_caller_identity" "current" {}

locals {
  name   = var.name
  region = var.region

  cluster_version = "1.34"

  # MSK configuration
  msk_broker_count = var.az_count
  msk_partition_count = var.msk_partition_count

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, var.az_count)

  tags = {
    Blueprint  = local.name
    GithubRepo = "github.com/aws-ia/terraform-aws-eks-blueprints"
  }

}

###############################################################
# EKS Cluster
###############################################################

module "eks" {
  source  = "terraform-aws-modules/eks/aws"
  version = "21.9.0"

  name               = local.name
  kubernetes_version = local.cluster_version

  endpoint_public_access = true

  vpc_id     = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  enable_cluster_creator_admin_permissions = true

  # Enable EKS AutoMode
  compute_config = {
    enabled    = true
    node_pools = ["general-purpose", "system"]
  }

  tags = local.tags
}

###############################################################
# VPC
###############################################################

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 4, k)]
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 48)]

  enable_nat_gateway = true
  single_nat_gateway = true

  public_subnet_tags = { "kubernetes.io/role/elb" = 1 }

  private_subnet_tags = { "kubernetes.io/role/internal-elb" = 1 }

  tags = local.tags
}

