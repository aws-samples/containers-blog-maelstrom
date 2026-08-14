#!/usr/bin/env bash
#
# 10-install-argocd.sh — Install Argo CD and the kro (Kube Resource Orchestrator)
# controller.
#
# ArgoCD gives us GitOps + a UI to watch sync status. kro lets us define
# higher-level custom APIs (ResourceGraphDefinitions) that fan out into the
# underlying Kubernetes objects — handy for packaging the demo app as a single
# resource. Both are installed (self-hosted) here so the cluster has "argocd and
# kro capabilities" out of the box.
#
set -euo pipefail

ARGOCD_VERSION="${ARGOCD_VERSION:-stable}"
KRO_VERSION="${KRO_VERSION:-0.2.3}"

echo "==> Installing Argo CD (${ARGOCD_VERSION})..."
kubectl create namespace argocd --dry-run=client -o yaml | kubectl apply -f -
# Use server-side apply: the Argo CD manifest contains very large CRDs (the
# ApplicationSet CRD alone exceeds the 262144-byte limit on the
# kubectl.kubernetes.io/last-applied-configuration annotation that CLIENT-side
# apply writes). Server-side apply doesn't store that annotation, so it avoids
# the "metadata.annotations: Too long" error. --force-conflicts lets re-runs
# take ownership of fields cleanly.
kubectl apply --server-side --force-conflicts -n argocd \
  -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"

echo "==> Waiting for Argo CD server to become ready..."
kubectl -n argocd rollout status deploy/argocd-server --timeout=300s

echo "==> Installing kro (${KRO_VERSION}) via Helm..."
# upgrade --install (not plain install) so re-running this script doesn't fail
# with "cannot re-use a name that is still in use".
helm upgrade --install kro oci://ghcr.io/kro-run/kro/kro \
  --namespace kro \
  --create-namespace \
  --version "${KRO_VERSION}"

kubectl -n kro rollout status deploy/kro --timeout=300s || true

echo ""
echo "==> Argo CD initial admin password:"
# Argo CD auto-generates the initial 'admin' password and stores it in the
# argocd-initial-admin-secret Secret. Decode it to log in.
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo ""

echo ""
echo "To log in to Argo CD:"
echo "  1. Port-forward the server:"
echo "       kubectl -n argocd port-forward svc/argocd-server 8080:443"
echo "  2. Open the UI:  https://localhost:8080"
echo "       Username: admin"
echo "       Password: the value printed above"
echo "  (Or via CLI:  argocd login localhost:8080 --username admin --password <password>)"
echo ""
echo "Next: ./scripts/20-install-argo-workflows-events.sh"
