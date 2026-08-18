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
#   export DEVLAKE_WEBHOOK_URL="http://devlake-ui.devlake.svc.cluster.local:4000/api/rest/plugins/webhook/connections/1/deployments"
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WORKFLOW_NS="${WORKFLOW_NS:-argo}"

echo "==> Applying the Argo Rollouts notification ConfigMap..."
kubectl apply -f "${ROOT_DIR}/platform/argo-rollouts/notifications-configmap.yaml"

# The DevLake webhook requires an API key. Script 52 stored it as DEVLAKE_TOKEN
# in the devlake-webhook-secret in the ${WORKFLOW_NS} (argo) namespace; the
# notification config sends it as "Authorization: Bearer <token>". Without it
# every deploy POST is rejected with HTTP 401 and nothing is recorded.
DEVLAKE_WEBHOOK_TOKEN="${DEVLAKE_WEBHOOK_TOKEN:-}"
if [[ -z "${DEVLAKE_WEBHOOK_TOKEN}" ]]; then
  DEVLAKE_WEBHOOK_TOKEN="$(kubectl -n "${WORKFLOW_NS}" get secret devlake-webhook-secret \
    -o jsonpath='{.data.DEVLAKE_TOKEN}' 2>/dev/null | base64 -d || true)"
fi
if [[ -z "${DEVLAKE_WEBHOOK_TOKEN}" ]]; then
  echo "    WARNING: no DevLake webhook token found (devlake-webhook-secret in" >&2
  echo "    the ${WORKFLOW_NS} namespace). Run scripts/52-setup-devlake-project.sh" >&2
  echo "    first, or export DEVLAKE_WEBHOOK_TOKEN. Deploy POSTs will 401 without it." >&2
fi

if [[ -n "${DEVLAKE_WEBHOOK_URL:-}" ]]; then
  echo "==> Creating the notification Secret (webhook URL + API token)..."
  kubectl -n argo-rollouts create secret generic argo-rollouts-notification-secret \
    --from-literal=devlake-webhook-url="${DEVLAKE_WEBHOOK_URL}" \
    --from-literal=devlake-webhook-token="${DEVLAKE_WEBHOOK_TOKEN}" \
    --dry-run=client -o yaml | kubectl apply -f -
else
  echo "==> DEVLAKE_WEBHOOK_URL not set — applying the template Secret."
  echo "    Edit platform/argo-rollouts/notifications-secret.yaml with your"
  echo "    connection id + token, or re-run with DEVLAKE_WEBHOOK_URL exported."
  kubectl apply -f "${ROOT_DIR}/platform/argo-rollouts/notifications-secret.yaml"
fi

echo "==> Restarting the Rollouts controller to pick up config..."
kubectl -n argo-rollouts rollout restart deploy/argo-rollouts
kubectl -n argo-rollouts rollout status deploy/argo-rollouts --timeout=180s

echo ""
echo "Done. Deploy changes with ./scripts/ship.sh and watch DevLake record them"
echo "automatically. Tail the controller to confirm notifications fire:"
echo "  kubectl -n argo-rollouts logs deploy/argo-rollouts -f | grep -i notif"
