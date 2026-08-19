#!/usr/bin/env bash
#
# 30-install-gitea.sh — Install Gitea, the self-hosted Git server DevLake reads.
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Adding the Gitea Helm repo..."
helm repo add gitea-charts https://dl.gitea.com/charts/ >/dev/null 2>&1 || true
helm repo update gitea-charts >/dev/null

echo "==> Installing Gitea..."
kubectl create namespace gitea --dry-run=client -o yaml | kubectl apply -f -
helm upgrade --install gitea gitea-charts/gitea \
  -n gitea \
  -f "${ROOT_DIR}/platform/gitea/values.yaml"

echo "==> Waiting for Gitea to become ready..."
kubectl -n gitea rollout status deploy/gitea --timeout=300s || \
  kubectl -n gitea rollout status statefulset/gitea --timeout=300s || true

echo ""
echo "Gitea UI (default creds gitea_admin / gitea_admin_pass):"
echo "  kubectl -n gitea port-forward svc/gitea-http 3000:3000"
echo "  open http://localhost:3000"
echo ""
echo "Next: ./scripts/40-install-argo-rollouts.sh"
