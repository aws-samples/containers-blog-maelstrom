terraform {
  required_version = ">= 1.0.0"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = ">= 3.72"
    }
    kubernetes = {
      source  = "hashicorp/kubernetes"
      version = ">= 2.10"
    }
    helm = {
      source  = "hashicorp/helm"
      version = ">= 2.4.1"
    }
  }
}

provider "aws" {}

provider "kubernetes" {
  host                   = module.eks_blueprints.cluster_endpoint
  cluster_ca_certificate = base64decode(module.eks_blueprints.cluster_certificate_authority_data)
  exec {
    api_version = "client.authentication.k8s.io/v1beta1"
    command     = "aws"
    # This requires the awscli to be installed locally where Terraform is executed
    args = ["eks", "get-token", "--cluster-name", module.eks_blueprints.cluster_name]
  }
}

provider "helm" {
  kubernetes {
    host                   = module.eks_blueprints.cluster_endpoint
    cluster_ca_certificate = base64decode(module.eks_blueprints.cluster_certificate_authority_data)
    exec {
      api_version = "client.authentication.k8s.io/v1beta1"
      command     = "aws"
      # This requires the awscli to be installed locally where Terraform is executed
      args = ["eks", "get-token", "--cluster-name", module.eks_blueprints.cluster_name]
    }
  }
}

data "aws_availability_zones" "available" {
  filter {
    name   = "opt-in-status"
    values = ["opt-in-not-required"]
  }
}

locals {
  name = "tah-demo-cluster"
  cluster_name = local.name

  vpc_cidr = "10.0.0.0/16"
  azs      = slice(data.aws_availability_zones.available.names, 0, 3)

  tags = {
    Blueprint  = local.cluster_name
  }
}

#---------------------------------------------------------------
# EKS Blueprints
#---------------------------------------------------------------

module "eks_blueprints" {
  source = "terraform-aws-modules/eks/aws"
  version = "~> 19.13"

  cluster_name    = local.cluster_name
  cluster_version = var.cluster_version

  vpc_id             = module.vpc.vpc_id
  subnet_ids = module.vpc.private_subnets

  cluster_endpoint_private_access = true
  cluster_endpoint_public_access  = true

  eks_managed_node_groups = {
    mg_5a = {
      node_group_name = "managed-ondemand-a"
      instance_types  = ["m5.xlarge"]
      min_size        = 1
      max_size        = 4
      desired_size    = var.num_nodes_az1
      subnet_ids      = [module.vpc.private_subnets[0]]

      additional_iam_policies = [
        "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess",
        "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
        "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
      ]
    }
    mg_5b = {
      node_group_name = "managed-ondemand-b"
      instance_types  = ["m5.xlarge"]
      min_size        = 1
      max_size        = 4
      desired_size    = var.num_nodes_az2
      subnet_ids      = [module.vpc.private_subnets[1]]

      additional_iam_policies = [
        "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess",
        "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
        "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
      ]
    }
    mg_5c = {
      node_group_name = "managed-ondemand-c"
      instance_types  = ["m5.xlarge"]
      min_size        = 1
      max_size        = 4
      desired_size    = var.num_nodes_az3
      subnet_ids      = [module.vpc.private_subnets[2]]

      additional_iam_policies = [
        "arn:aws:iam::aws:policy/AWSXrayWriteOnlyAccess",
        "arn:aws:iam::aws:policy/CloudWatchAgentServerPolicy",
        "arn:aws:iam::aws:policy/AmazonPrometheusRemoteWriteAccess"
      ]
    }
  }

  tags = local.tags
}

module "eks_blueprints_kubernetes_addons" {
  source = "aws-ia/eks-blueprints-addons/aws"
  version = "~> 1.0"

  cluster_name         = module.eks_blueprints.cluster_name
  cluster_endpoint     = module.eks_blueprints.cluster_endpoint
  cluster_version      = module.eks_blueprints.cluster_version
  oidc_provider_arn    = module.eks_blueprints.oidc_provider_arn

  # EKS Managed Add-ons
  eks_addons = {
    aws-ebs-csi-driver = {
      most_recent = true
    }
    coredns = {
      most_recent = true
    }
    vpc-cni = {
      most_recent = true
    }
    kube-proxy = {
      most_recent = true
    }
    adot = {
      most_recent = true
    }
  }

  # Add-ons
  enable_aws_load_balancer_controller = true
  enable_metrics_server               = true
  enable_cert_manager                 = true

  tags = local.tags

  depends_on = [
    module.eks_blueprints
  ]
}

#---------------------------------------------------------------
# Supporting Resources
#---------------------------------------------------------------

module "vpc" {
  source  = "terraform-aws-modules/vpc/aws"
  version = "~> 5.0"

  name = local.name
  cidr = local.vpc_cidr

  azs             = local.azs
  public_subnets  = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k)]
  private_subnets = [for k, v in local.azs : cidrsubnet(local.vpc_cidr, 8, k + 10)]

  enable_nat_gateway   = true
  single_nat_gateway   = true
  enable_dns_hostnames = true

  # Manage so we can name
  manage_default_network_acl    = true
  default_network_acl_tags      = { Name = "${local.name}-default" }
  manage_default_route_table    = true
  default_route_table_tags      = { Name = "${local.name}-default" }
  manage_default_security_group = true
  default_security_group_tags   = { Name = "${local.name}-default" }

  public_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/elb"                      = 1
  }

  private_subnet_tags = {
    "kubernetes.io/cluster/${local.cluster_name}" = "shared"
    "kubernetes.io/role/internal-elb"             = 1
  }

  tags = local.tags
}


output "configure_kubectl" {
  description = "Configure kubectl: make sure you're logged in with the correct AWS profile and run the following command to update your kubeconfig"
  value       = "aws eks update-kubeconfig --name ${module.eks_blueprints.cluster_name}"
}
