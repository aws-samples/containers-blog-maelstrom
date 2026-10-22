#!/usr/bin/env bash
#
# 50-install-devlake.sh — Install Apache DevLake with MySQL + Grafana enabled.
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Adding the DevLake Helm repo..."
# DevLake graduated from the Apache incubator; the old
# incubator-devlake-helm-chart repo no longer serves a valid index.
# --force-update makes re-runs replace any stale URL cached under this name.
helm repo add devlake https://apache.github.io/devlake-helm-chart --force-update >/dev/null
helm repo update devlake >/dev/null

echo "==> Installing DevLake (MySQL + Grafana + config-ui)..."
kubectl create namespace devlake --dry-run=client -o yaml | kubectl apply -f -

# Credentials live in Secrets rather than values.yaml. Generate them on first
# install only; re-runs keep the existing values (MySQL's data volume and the
# lake's stored connection credentials depend on them staying stable).
if ! kubectl -n devlake get secret devlake-mysql-auth >/dev/null 2>&1; then
  echo "==> Creating devlake-mysql-auth with generated MySQL passwords..."
  kubectl -n devlake create secret generic devlake-mysql-auth \
    --from-literal=MYSQL_PASSWORD="$(openssl rand -hex 16)" \
    --from-literal=MYSQL_ROOT_PASSWORD="$(openssl rand -hex 16)"
fi
if ! kubectl -n devlake get secret devlake-encryption-secret >/dev/null 2>&1; then
  echo "==> Creating devlake-encryption-secret with a generated encryption key..."
  kubectl -n devlake create secret generic devlake-encryption-secret \
    --from-literal=ENCRYPTION_SECRET="$(openssl rand -base64 2000 | tr -dc 'A-Z' | head -c 128)"
fi

helm upgrade --install devlake devlake/devlake \
  -n devlake \
  -f "${ROOT_DIR}/platform/devlake/values.yaml"

echo "==> Waiting for DevLake components (this can take a few minutes)..."
kubectl -n devlake rollout status deploy/devlake-lake --timeout=600s || true
kubectl -n devlake rollout status deploy/devlake-grafana --timeout=600s || true

echo ""
echo "DevLake config UI (also serves Grafana under /grafana):"
echo "  kubectl -n devlake port-forward svc/devlake-ui 4000:4000"
echo "  open http://localhost:4000"
echo ""
echo "Grafana DORA dashboards — served by the config UI proxy."
echo "Do NOT port-forward Grafana directly: it is pinned to serve at /grafana and"
echo "redirects to localhost:3000, which collides with Gitea. Use the 4000 tunnel:"
echo "  open http://localhost:4000/grafana/"
echo "Login: user 'admin'; the password is generated — fetch it with:"
echo "  kubectl -n devlake get secret devlake-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo"
echo ""
echo "Next: configure the Gitea connection + a blueprint, then deploy the demo"
echo "app. See README.md sections 6-8."
