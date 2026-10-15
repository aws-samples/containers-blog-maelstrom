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

# Admin credentials live in a Secret rather than values.yaml. Generate a random
# password on first install only; re-runs keep the existing one.
if ! kubectl -n gitea get secret gitea-admin-secret >/dev/null 2>&1; then
  echo "==> Creating gitea-admin-secret with a generated admin password..."
  kubectl -n gitea create secret generic gitea-admin-secret \
    --from-literal=username="${GITEA_ADMIN_USER:-gitea_admin}" \
    --from-literal=password="${GITEA_ADMIN_PASS:-$(openssl rand -hex 16)}"
fi

helm upgrade --install gitea gitea-charts/gitea \
  -n gitea \
  -f "${ROOT_DIR}/platform/gitea/values.yaml"

echo "==> Waiting for Gitea to become ready..."
kubectl -n gitea rollout status deploy/gitea --timeout=300s || \
  kubectl -n gitea rollout status statefulset/gitea --timeout=300s || true

echo ""
echo "Gitea UI (user gitea_admin; password: ./scripts/get-credentials.sh)"
echo "  kubectl -n gitea port-forward svc/gitea-http 3000:3000"
echo "  open http://localhost:3000"
echo ""
echo "Next: ./scripts/40-install-argo-rollouts.sh"
