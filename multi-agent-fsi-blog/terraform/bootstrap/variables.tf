variable "aws_region" {
  description = "AWS region hosting the EKS cluster"
  type        = string
  default     = "us-west-2"
}

variable "cluster_name" {
  description = "EKS cluster name (must match the cluster stack output)"
  type        = string
  default     = "finops-agents"
}

variable "argocd_chart_version" {
  description = "argo-cd Helm chart version"
  type        = string
  default     = "7.6.12"
}

variable "argocd_domain" {
  description = "Optional DNS name for the ArgoCD UI (ingress wired separately)"
  type        = string
  default     = "argocd.example.com"
}

variable "gitops_repo_url" {
  description = "Git repository URL hosting the multi-agent-fsi-blog/gitops tree"
  type        = string
  default     = "https://github.com/aws-samples/containers-blog-maelstrom"
}

variable "gitops_repo_branch" {
  description = "Branch ArgoCD should track"
  type        = string
  default     = "multi-agent-fsi-blog"
}

variable "gitops_root_path" {
  description = "Path to the app-of-apps root within the repo"
  type        = string
  default     = "multi-agent-fsi-blog/gitops/root"
}
