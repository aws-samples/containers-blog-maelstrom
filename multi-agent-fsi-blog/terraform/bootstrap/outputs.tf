output "argocd_namespace" {
  description = "Namespace hosting ArgoCD"
  value       = kubernetes_namespace.argocd.metadata[0].name
}

output "argocd_initial_admin_secret_cmd" {
  description = "Run this to get the bootstrap admin password"
  value       = "kubectl get secret -n argocd argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d"
}

output "argocd_port_forward_cmd" {
  description = "Run this to access the ArgoCD UI locally"
  value       = "kubectl port-forward -n argocd svc/argocd-server 8080:80"
}

output "root_application_name" {
  description = "Name of the app-of-apps root Application"
  value       = "platform-root"
}
