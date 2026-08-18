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
