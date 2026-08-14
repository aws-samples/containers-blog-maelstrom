#!/usr/bin/env bash
#
# 55-configure-gitea-webhooks.sh — Wire Gitea issue + pull-request webhooks into
# DevLake via Argo Events / Argo Workflows.
#
# Pipeline this sets up:
#
#   Gitea (issues, pull_request)
#     --webhook POST-->  Argo Events EventSource (gitea-webhook, :12000/gitea)
#     --routes by X-Gitea-Event header-->  Sensor (gitea-dora)
#     --submits-->  WorkflowTemplate (dora-incident-workflow | dora-pull-request-workflow)
#     --jq transform + POST-->  DevLake Incoming Webhook (issues | pull_requests)
#
# Deployments are handled separately by the Argo Rollouts notifications
# (scripts/60-configure-rollout-notifications.sh); this script covers the
# Git-activity events (issues -> incidents, PRs -> code-review metrics).
#
# Prerequisites:
#   - scripts/20-install-argo-workflows-events.sh has been run (argo + argo-events)
#   - scripts/30-install-gitea.sh has been run
#   - scripts/52-setup-devlake-project.sh has been run — it creates the DevLake
#     webhook connection AND writes devlake-webhook-secret / devlake-webhook-id
#     into the argo namespace, which the WorkflowTemplates consume. This script
#     does NOT create those; run 52 first.
#
# Config via env vars (all optional; sane fallbacks applied):
#   GITEA_ADMIN_USER         Gitea user that owns the repo       (default: gitea_admin)
#   GITEA_ADMIN_PASS         Gitea password/token                (default: gitea_admin_pass)
#   GITEA_REPO               repo to add the webhook to          (default: dora-demo)
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
WEBHOOK_DIR="${ROOT_DIR}/platform/webhooks"

# shellcheck source=lib/pf.sh
source "${ROOT_DIR}/scripts/lib/pf.sh"

GITEA_ADMIN_USER="${GITEA_ADMIN_USER:-gitea_admin}"
GITEA_ADMIN_PASS="${GITEA_ADMIN_PASS:-gitea_admin_pass}"
GITEA_REPO="${GITEA_REPO:-dora-demo}"

# Base URL of the Gitea HTTP endpoint (the API lives under /api/v1). Defaults to
# the local port-forward; override to point at an existing tunnel or ingress.
GITEA_BASE="${GITEA_BASE:-http://localhost:3000}"

# The in-cluster URL Gitea should POST to (the EventSource Service).
EVENTSOURCE_URL="http://gitea-webhook-eventsource-svc.argo-events.svc.cluster.local:12000/gitea"

echo "==> Verifying DevLake webhook credentials exist (from script 52)..."
if ! kubectl -n argo get secret devlake-webhook-secret >/dev/null 2>&1 \
   || ! kubectl -n argo get configmap devlake-webhook-id >/dev/null 2>&1; then
  echo "    Missing devlake-webhook-secret / devlake-webhook-id in the argo namespace."
  echo "    Run ./scripts/52-setup-devlake-project.sh first — it creates the DevLake"
  echo "    webhook connection and writes these credentials."
  exit 1
fi

echo "==> Applying WorkflowTemplates (issue + pull-request transforms)..."
kubectl apply -f "${WEBHOOK_DIR}/dora-workflowtemplates.yaml"

echo "==> Applying Sensor RBAC (lets the Sensor submit Workflows into argo)..."
kubectl apply -f "${WEBHOOK_DIR}/gitea-sensor-rbac.yaml"

echo "==> Applying the Gitea EventSource + Sensor..."
kubectl apply -f "${WEBHOOK_DIR}/gitea-eventsource.yaml"
kubectl apply -f "${WEBHOOK_DIR}/gitea-sensor.yaml"

echo "==> Waiting for the EventSource + Sensor pods to become ready..."
kubectl -n argo-events wait --for=condition=Ready pod \
  -l eventsource-name=gitea-webhook --timeout=120s || true
kubectl -n argo-events wait --for=condition=Ready pod \
  -l sensor-name=gitea-dora --timeout=120s || true

# ---------------------------------------------------------------------------
# Register the webhook in Gitea via its API (idempotent-ish: creates a new one).
# ---------------------------------------------------------------------------
echo "==> Registering the webhook in Gitea repo ${GITEA_ADMIN_USER}/${GITEA_REPO}..."

# Reach Gitea, auto-starting a temporary port-forward if the default localhost
# URL isn't already reachable. Skipped if GITEA_BASE points elsewhere.
if [[ "${GITEA_BASE}" == http://localhost:3000* ]]; then
  ensure_pf "${GITEA_BASE}" gitea gitea-http 3000:3000 || true
fi

GITEA_API="${GITEA_API:-${GITEA_BASE}}/api/v1"
HOOK_PAYLOAD=$(cat <<JSON
{
  "type": "gitea",
  "active": true,
  "events": ["issues", "pull_request"],
  "config": {
    "url": "${EVENTSOURCE_URL}",
    "content_type": "json"
  }
}
JSON
)

if curl -sS -f -X POST "${GITEA_API}/repos/${GITEA_ADMIN_USER}/${GITEA_REPO}/hooks" \
     -u "${GITEA_ADMIN_USER}:${GITEA_ADMIN_PASS}" \
     -H 'Content-Type: application/json' \
     -d "${HOOK_PAYLOAD}" >/dev/null; then
  echo "    Webhook created."
else
  echo "    Could not create the webhook automatically (is the port-forward up,"
  echo "    and does repo ${GITEA_REPO} exist?). Add it manually in the Gitea UI:"
  echo "      Repo -> Settings -> Webhooks -> Add Webhook -> Gitea"
  echo "      Target URL:   ${EVENTSOURCE_URL}"
  echo "      Content type: application/json"
  echo "      Events:       Issues, Pull Request"
fi

echo ""
echo "Done. Test it: open or close an issue / open or merge a PR in Gitea, then"
echo "watch the workflow fire and check the DevLake record:"
echo "  kubectl -n argo get workflows -l app.kubernetes.io/component=dora-webhooks -w"
echo "  kubectl -n argo-events logs -l sensor-name=gitea-dora -f"
