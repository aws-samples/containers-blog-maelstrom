#!/usr/bin/env bash
#
# 52-setup-devlake-project.sh — Create the DevLake project, webhook connection,
# and blueprint that make the DORA metrics computable.
#
# DevLake computes DORA metrics at the PROJECT level, and only when a blueprint
# runs. This script (adapted from the reference dora-setup WorkflowTemplate)
# talks directly to the DevLake lake backend API and:
#
#   1. runs any pending DB migrations       GET  /proceed-db-migration
#   2. creates a project with the dora +    POST /projects
#      issue_trace metrics enabled          (this also creates its blueprint)
#   3. creates an Incoming Webhook           POST /plugins/webhook/connections
#      connection                           (returns the connection id + apiKey)
#   4. attaches the webhook connection to    PATCH /blueprints/:id
#      the project's blueprint
#   5. writes the connection id + api key into the devlake-webhook-secret /
#      devlake-webhook-id (ConfigMap) in the `argo` namespace, where the Gitea
#      webhook WorkflowTemplates read them (see 55-configure-gitea-webhooks.sh).
#      It also stores the blueprint id (DEVLAKE_BP_ID) so 70-calculate-metrics.sh
#      knows which blueprint to trigger.
#
# NOTE on the API base URL: the lake backend serves its routes at the ROOT of
# port 8080 (e.g. /projects), NOT under /api/rest — that prefix only exists on
# the config-ui proxy (:4000). Point DEVLAKE_API at the lake service.
#
# Prerequisites: scripts/50-install-devlake.sh has been run.
#
# Config via env vars:
#   PROJECT_NAME     DevLake project name          (default: dora-demo)
#   DEVLAKE_API      lake backend base URL          (default: http://localhost:8080)
#                    If using the default, port-forward the lake service first:
#                      kubectl -n devlake port-forward svc/devlake-lake 8080:8080
#   WORKFLOW_NS      namespace the webhook Workflows run in (default: argo)
#   COLLECT_SINCE    only collect data after this RFC3339 time (default: 2024-01-01T00:00:00Z)
#
set -euo pipefail

PROJECT_NAME="${PROJECT_NAME:-dora-demo}"
DEVLAKE_API="${DEVLAKE_API:-http://localhost:8080}"
WORKFLOW_NS="${WORKFLOW_NS:-argo}"
COLLECT_SINCE="${COLLECT_SINCE:-2024-01-01T00:00:00Z}"

# shellcheck source=lib/pf.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/pf.sh"

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

# Reach the lake backend, auto-starting a temporary port-forward if the default
# localhost URL isn't already reachable. Skipped if DEVLAKE_API points elsewhere.
if [[ "${DEVLAKE_API}" == http://localhost:8080* ]]; then
  ensure_pf "${DEVLAKE_API}/ping" devlake devlake-lake 8080:8080
fi

echo "==> Checking DevLake API reachability at ${DEVLAKE_API}..."
if ! curl -sS -f "${DEVLAKE_API}/ping" >/dev/null 2>&1; then
  echo "    Can't reach ${DEVLAKE_API}. If you set a custom DEVLAKE_API, make sure"
  echo "    it's reachable; otherwise port-forward the lake backend:"
  echo "      kubectl -n devlake port-forward svc/devlake-lake 8080:8080"
  exit 1
fi

# DevLake gates schema migrations behind an explicit trigger: on first boot (or
# after an upgrade) it detects pending migrations and returns HTTP 428 on every
# real API call until GET /proceed-db-migration is called AND the migrations
# finish. So we trigger it, then WAIT until the API stops returning 428 before
# doing anything else — otherwise project creation races the migration and fails.
echo "==> Triggering any pending DB migrations..."
curl -sS -X GET "${DEVLAKE_API}/proceed-db-migration" >/dev/null || true

echo "==> Waiting for migrations to complete (up to ${MIGRATION_TIMEOUT:-600}s)..."
migration_deadline=$(( SECONDS + ${MIGRATION_TIMEOUT:-600} ))
while :; do
  probe="$(curl -sS "${DEVLAKE_API}/projects" 2>/dev/null || true)"
  if ! echo "${probe}" | grep -q 'migration in progress'; then
    echo "    Migrations complete; API is ready."
    break
  fi
  if (( SECONDS >= migration_deadline )); then
    echo "    Timed out waiting for migrations. The lake may be wedged (e.g. its" >&2
    echo "    DB connection dropped mid-migration). Restart it and re-run:" >&2
    echo "      kubectl -n devlake rollout restart deploy/devlake-lake" >&2
    exit 1
  fi
  # Re-trigger in case the proceed request landed before the lake was listening.
  curl -sS -X GET "${DEVLAKE_API}/proceed-db-migration" >/dev/null 2>&1 || true
  sleep 5
done

echo "==> Creating project '${PROJECT_NAME}' (dora + issue_trace metrics)..."
project_req=$(jq -n --arg name "${PROJECT_NAME}" '{
  name: $name,
  description: "DORA showcase project",
  metrics: [
    { pluginName: "dora",        pluginOption: {}, enable: true },
    { pluginName: "issue_trace", pluginOption: {}, enable: true }
  ]
}')
project_resp=$(curl -sS -X POST -H "Content-Type: application/json" \
  "${DEVLAKE_API}/projects" -d "${project_req}")

blueprint_id=$(echo "${project_resp}" | jq -r '.blueprint.id // empty')
blueprint_name=$(echo "${project_resp}" | jq -r '.blueprint.name // empty')
if [[ -z "${blueprint_id}" ]]; then
  if echo "${project_resp}" | grep -q 'migration in progress'; then
    echo "    DevLake is still applying DB migrations (HTTP 428). If this persists," >&2
    echo "    the lake is likely wedged — restart it and re-run this script:" >&2
    echo "      kubectl -n devlake rollout restart deploy/devlake-lake" >&2
  else
    echo "    Project create response had no blueprint id — it may already exist."
    echo "    Response was:"; echo "${project_resp}" | jq '.' 2>/dev/null || echo "${project_resp}"
    echo "    Delete the existing '${PROJECT_NAME}' project in the UI and re-run, or"
    echo "    set PROJECT_NAME to a fresh name."
  fi
  exit 1
fi
echo "    blueprint id=${blueprint_id} name=${blueprint_name}"

echo "==> Creating Incoming Webhook connection '${PROJECT_NAME}_webhook'..."
webhook_req=$(jq -n --arg name "${PROJECT_NAME}_webhook" '{ name: $name }')
webhook_resp=$(curl -sS -X POST -H "Content-Type: application/json" \
  "${DEVLAKE_API}/plugins/webhook/connections" -d "${webhook_req}")
webhook_id=$(echo "${webhook_resp}" | jq -r '.id // empty')
webhook_apikey=$(echo "${webhook_resp}" | jq -r '.apiKey.apiKey // empty')
if [[ -z "${webhook_id}" ]]; then
  echo "    Failed to create webhook connection. Response:"
  echo "${webhook_resp}" | jq '.' 2>/dev/null || echo "${webhook_resp}"
  exit 1
fi
echo "    webhook connection id=${webhook_id}"

echo "==> Attaching the webhook connection to the project's blueprint..."
bp_patch=$(jq -n \
  --arg name "${blueprint_name}" \
  --arg project "${PROJECT_NAME}" \
  --arg since "${COLLECT_SINCE}" \
  --argjson bpid "${blueprint_id}" \
  --argjson connid "${webhook_id}" '{
    name: $name,
    projectName: $project,
    mode: "NORMAL",
    enable: true,
    cronConfig: "0 0 * * 1",
    isManual: false,
    connections: [ { pluginName: "webhook", connectionId: $connid } ],
    skipOnFail: false,
    timeAfter: $since,
    id: $bpid
  }')
curl -sS -X PATCH -H "Content-Type: application/json" \
  "${DEVLAKE_API}/blueprints/${blueprint_id}" -d "${bp_patch}" >/dev/null

echo "==> Writing webhook credentials into the ${WORKFLOW_NS} namespace..."
# These are what platform/webhooks/dora-workflowtemplates.yaml mounts via envFrom.
kubectl -n "${WORKFLOW_NS}" create secret generic devlake-webhook-secret \
  --from-literal=DEVLAKE_TOKEN="${webhook_apikey}" \
  --dry-run=client -o yaml | kubectl apply -f -
kubectl -n "${WORKFLOW_NS}" create configmap devlake-webhook-id \
  --from-literal=DEVLAKE_HOOK_ID="${webhook_id}" \
  --from-literal=DEVLAKE_BP_ID="${blueprint_id}" \
  --dry-run=client -o yaml | kubectl apply -f -

echo ""
echo "Project setup complete."
echo "  Project:            ${PROJECT_NAME}"
echo "  Blueprint id:       ${blueprint_id}"
echo "  Webhook conn id:    ${webhook_id}"
echo ""
echo "Use these for the deployment webhook (section 7.2 / script 60)."
echo "NOTE: the /api/rest prefix is served by the config-ui proxy (:4000). If you"
echo "post to the lake backend (:8080) directly, drop the prefix. Config-ui form:"
echo "  export DEVLAKE_WEBHOOK_URL=\"http://devlake-ui.devlake.svc.cluster.local:4000/api/rest/plugins/webhook/connections/${webhook_id}/deployments\""
echo ""
echo "Next: ./scripts/55-configure-gitea-webhooks.sh  (Gitea issue/PR webhooks)"
echo "Then: generate some data, and ./scripts/70-calculate-metrics.sh to compute DORA."
