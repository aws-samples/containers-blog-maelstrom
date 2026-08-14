#!/usr/bin/env bash
#
# 70-calculate-metrics.sh — Trigger the DevLake blueprint so the DORA plugin
# computes metrics, then wait for the resulting pipeline to finish.
#
# DevLake doesn't compute DORA metrics continuously — it does so when a project's
# blueprint runs. After you've generated some data (deployments via ship.sh,
# issues/PRs via the Gitea webhooks), run this to (re)compute the metrics so they
# show up in Grafana. It:
#
#   1. triggers the project's blueprint     POST /blueprints/:id/trigger
#      (returns a pipeline)
#   2. polls the pipeline until it reaches   GET  /pipelines/:id
#      a terminal status (TASK_COMPLETED / TASK_FAILED / TASK_PARTIAL)
#
# The lake backend serves routes at the ROOT of :8080 (no /api/rest prefix).
#
# Prerequisites: scripts/52-setup-devlake-project.sh has been run (it stored the
# blueprint id in the devlake-webhook-id ConfigMap as DEVLAKE_BP_ID).
#
# Config via env vars:
#   DEVLAKE_API      lake backend base URL   (default: http://localhost:8080)
#                    Port-forward first if using the default:
#                      kubectl -n devlake port-forward svc/devlake-lake 8080:8080
#   DEVLAKE_BP_ID    blueprint id to trigger (default: read from the ConfigMap)
#   WORKFLOW_NS      namespace holding the ConfigMap (default: argo)
#   FULL_SYNC        "true" to re-collect everything (default: false)
#   POLL_TIMEOUT     seconds to wait for the pipeline (default: 900)
#
set -euo pipefail

DEVLAKE_API="${DEVLAKE_API:-http://localhost:8080}"
WORKFLOW_NS="${WORKFLOW_NS:-argo}"
FULL_SYNC="${FULL_SYNC:-false}"
POLL_TIMEOUT="${POLL_TIMEOUT:-900}"

# shellcheck source=lib/pf.sh
source "$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)/lib/pf.sh"

command -v jq >/dev/null || { echo "jq is required" >&2; exit 1; }

# Resolve the blueprint id: explicit env var wins, else read the ConfigMap that
# script 52 populated.
DEVLAKE_BP_ID="${DEVLAKE_BP_ID:-}"
if [[ -z "${DEVLAKE_BP_ID}" ]]; then
  DEVLAKE_BP_ID="$(kubectl -n "${WORKFLOW_NS}" get configmap devlake-webhook-id \
    -o jsonpath='{.data.DEVLAKE_BP_ID}' 2>/dev/null || true)"
fi
if [[ -z "${DEVLAKE_BP_ID}" ]]; then
  echo "No blueprint id. Set DEVLAKE_BP_ID, or run scripts/52-setup-devlake-project.sh" >&2
  echo "first so it's stored in the devlake-webhook-id ConfigMap." >&2
  exit 1
fi

# Reach the lake backend, auto-starting a temporary port-forward if the default
# localhost URL isn't already reachable. Skipped if DEVLAKE_API points elsewhere.
if [[ "${DEVLAKE_API}" == http://localhost:8080* ]]; then
  ensure_pf "${DEVLAKE_API}/ping" devlake devlake-lake 8080:8080
fi

echo "==> Checking DevLake API reachability at ${DEVLAKE_API}..."
if ! curl -sS -f "${DEVLAKE_API}/ping" >/dev/null 2>&1; then
  echo "    Can't reach ${DEVLAKE_API}. Port-forward the lake backend:" >&2
  echo "      kubectl -n devlake port-forward svc/devlake-lake 8080:8080" >&2
  exit 1
fi

echo "==> Triggering blueprint ${DEVLAKE_BP_ID} (fullSync=${FULL_SYNC})..."
trigger_body=$(jq -n --argjson full "${FULL_SYNC}" \
  '{ skipCollectors: false, fullSync: $full }')
pipeline_resp=$(curl -sS -X POST -H "Content-Type: application/json" \
  "${DEVLAKE_API}/blueprints/${DEVLAKE_BP_ID}/trigger" -d "${trigger_body}")
pipeline_id=$(echo "${pipeline_resp}" | jq -r '.id // empty')
if [[ -z "${pipeline_id}" ]]; then
  echo "    Trigger failed. Response:" >&2
  echo "${pipeline_resp}" | jq '.' 2>/dev/null || echo "${pipeline_resp}"
  exit 1
fi
echo "    Started pipeline id=${pipeline_id}"

echo "==> Waiting for pipeline ${pipeline_id} to finish (timeout ${POLL_TIMEOUT}s)..."
elapsed=0
interval=10
while :; do
  status=$(curl -sS "${DEVLAKE_API}/pipelines/${pipeline_id}" | jq -r '.status // "UNKNOWN"')
  case "${status}" in
    TASK_COMPLETED)
      echo "    Pipeline completed successfully."
      break
      ;;
    TASK_FAILED)
      echo "    Pipeline FAILED. Inspect it in the DevLake UI (Advanced -> Pipelines)." >&2
      exit 1
      ;;
    TASK_PARTIAL)
      echo "    Pipeline finished with partial success (some tasks failed)."
      break
      ;;
    *)
      if (( elapsed >= POLL_TIMEOUT )); then
        echo "    Timed out after ${POLL_TIMEOUT}s (last status: ${status})." >&2
        echo "    It may still finish — check the DevLake UI." >&2
        exit 1
      fi
      echo "    status=${status} (${elapsed}s elapsed)..."
      sleep "${interval}"
      elapsed=$(( elapsed + interval ))
      ;;
  esac
done

echo ""
echo "Metrics computed. View the DORA dashboards in Grafana:"
echo "  kubectl -n devlake port-forward svc/devlake-grafana 3001:3000"
echo "  open http://localhost:3001   (admin / admin)"
