#!/usr/bin/env bash
#
# 10-install-argocd.sh — Install Argo CD (self-hosted) so the demo app is
# deployed by GitOps: Argo CD watches the dora-demo repo in Gitea and syncs it
# onto the cluster (the Application itself is created by
# 65-deploy-demo-app.sh, once Gitea is seeded).
#
# Why self-hosted rather than the EKS Argo CD capability: the managed capability
# runs outside the cluster and reaches private Git servers only via
# CodeConnections (GitHub Enterprise Server / GitLab self-managed). It can't
# reach the in-cluster, ClusterIP-only Gitea this walkthrough uses, and it also
# requires AWS IAM Identity Center for login.
#
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"

echo "==> Installing Argo CD (${ARGOCD_VERSION})..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# Server-side apply: the Argo CD manifest contains very large CRDs (the
# ApplicationSet CRD alone exceeds the 262144-byte limit on the
# kubectl.kubernetes.io/last-applied-configuration annotation that CLIENT-side
# apply writes). --force-conflicts lets re-runs take ownership of fields cleanly.
kubectl apply --server-side --force-conflicts -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> Waiting for Argo CD to become ready..."
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s
kubectl -n argocd rollout status deploy/argocd-repo-server --timeout=300s
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=300s

echo ""
echo "Argo CD UI (user admin; the generated password is printed by"
echo "./scripts/get-credentials.sh):"
echo "  kubectl -n argocd port-forward svc/argocd-server 8443:443"
echo "  open https://localhost:8443"
echo ""
echo "Next: ./scripts/20-install-argo-workflows-events.sh"
