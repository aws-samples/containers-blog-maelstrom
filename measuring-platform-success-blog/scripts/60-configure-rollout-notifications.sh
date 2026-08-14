#!/usr/bin/env bash
#
# 60-configure-rollout-notifications.sh — Wire Argo Rollouts to DevLake so
# deployments are recorded automatically (no manual curl).
#
# This installs:
#   - the notification ConfigMap (triggers + DevLake webhook payload templates)
#   - the Secret holding the DevLake webhook URL
#
# The Rollout itself (app/rollout.yaml) is already annotated to subscribe to the
# triggers, so once this runs, every promote/abort records a deployment on its
# own.
#
# Set DEVLAKE_WEBHOOK_URL to the *in-cluster* DevLake webhook deployments URL
# before running. The /api/rest prefix is served by the config-ui proxy (:4000):
#   export DEVLAKE_WEBHOOK_URL="http://devlake-config-ui.devlake.svc.cluster.local:4000/api/rest/plugins/webhook/connections/1/deployments"
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"

echo "==> Applying the Argo Rollouts notification ConfigMap..."
kubectl apply -f "${ROOT_DIR}/platform/argo-rollouts/notifications-configmap.yaml"

if [[ -n "${DEVLAKE_WEBHOOK_URL:-}" ]]; then
  echo "==> Creating the notification Secret from DEVLAKE_WEBHOOK_URL..."
  kubectl -n argo-rollouts create secret generic argo-rollouts-notification-secret \
    --from-literal=devlake-webhook-url="${DEVLAKE_WEBHOOK_URL}" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  echo "==> DEVLAKE_WEBHOOK_URL not set — applying the template Secret."
  echo "    Edit platform/argo-rollouts/notifications-secret.yaml with your"
  echo "    connection id, or re-run with DEVLAKE_WEBHOOK_URL exported."
  kubectl apply -f "${ROOT_DIR}/platform/argo-rollouts/notifications-secret.yaml"
fi

echo "==> Restarting the Rollouts controller to pick up config..."
kubectl -n argo-rollouts rollout restart deploy/argo-rollouts
kubectl -n argo-rollouts rollout status deploy/argo-rollouts --timeout=180s

echo ""
echo "Done. Deploy changes with ./scripts/ship.sh and watch DevLake record them"
echo "automatically. Tail the controller to confirm notifications fire:"
echo "  kubectl -n argo-rollouts logs deploy/argo-rollouts -f | grep -i notif"
