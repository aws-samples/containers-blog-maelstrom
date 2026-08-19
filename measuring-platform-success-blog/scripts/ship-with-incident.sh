#!/usr/bin/env bash
#
# ship-with-incident.sh — Change Failure Rate helper.
#
# Ships a deployment, promotes it to Healthy, then opens a Gitea issue (an
# incident) against it — the pattern DevLake needs to register a change failure.
#
# How CFR works here: a DevLake "incident" is a Gitea issue (the webhook records
# each issue with type=INCIDENT). DevLake links an incident to a deployment BY
# TIMESTAMP — the deployment whose finish time is just before the issue's
# createdDate is marked a change failure. So this script deploys first, then
# opens the issue, so the incident attaches to the deployment we just shipped.
# CFR = deployments followed by an incident ÷ total deployments. (The rollout
# outcome itself does not drive CFR — the incident does.)
#
# For Time to Restore Service, resolve the incident later by closing the issue
# (in the Gitea UI, or via the API — the command is printed at the end of this
# run). DevLake measures restore time as the issue's open -> close span.
#
# Prerequisites:
#   - Gitea reachable at ${GITEA_BASE} (default http://localhost:3000 — run
#     ./scripts/port-forward.sh first) and the issue webhook wired up
#     (scripts/55-configure-gitea-webhooks.sh).
#   - kubectl-argo-rollouts, curl, jq.
#
# Usage:
#   ./scripts/ship-with-incident.sh [image-tag]   # default tag: red
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TAG="${1:-${TAG:-red}}"
NS="${NS:-dora-demo}"
ROLLOUT="${ROLLOUT:-dora-demo}"
GITEA_BASE="${GITEA_BASE:-http://localhost:3000}"
GITEA_USER="${GITEA_USER:-gitea_admin}"
GITEA_PASS="${GITEA_PASS:-gitea_admin_pass}"
GITEA_REPO="${GITEA_REPO:-dora-demo}"

for bin in kubectl curl jq; do
  command -v "$bin" >/dev/null || { echo "$bin is required" >&2; exit 1; }
done

GT="http://${GITEA_USER}:${GITEA_PASS}@${GITEA_BASE#http://}/api/v1/repos/${GITEA_USER}/${GITEA_REPO}"

echo "==> Shipping tag=${TAG}..."
"${SCRIPT_DIR}/ship.sh" "${TAG}"

echo "==> Waiting for the rollout to reach the manual pause..."
until [[ "$(kubectl -n "${NS}" get rollout "${ROLLOUT}" -o jsonpath='{.status.phase}' 2>/dev/null)" == "Paused" ]]; do
  sleep 3
done

echo "==> Promoting to Healthy (records the deployment)..."
kubectl argo rollouts promote "${ROLLOUT}" -n "${NS}" --full
kubectl argo rollouts status "${ROLLOUT}" -n "${NS}"

echo "==> Opening an incident against the deployment we just shipped..."
title="Production incident after deploy $(date -u +%FT%TZ)"
issue_num=$(curl -sS -X POST "${GT}/issues" -H 'Content-Type: application/json' \
  -d "{\"title\":\"${title}\",\"body\":\"Incident opened by ship-with-incident.sh\"}" \
  | jq -r '.number // empty')
[[ -n "${issue_num}" ]] || { echo "    Failed to open issue (is Gitea reachable + repo correct?)" >&2; exit 1; }

echo ""
echo "Done. Deployed '${TAG}' and opened incident issue #${issue_num}."
echo "DevLake will mark that deployment a change failure (linked by timestamp)."
echo "Update the metrics:        ./scripts/70-calculate-metrics.sh"
echo "Restore (Time to Restore): close the issue, then recompute:"
echo "  curl -sS -X PATCH \"${GITEA_BASE}/api/v1/repos/${GITEA_USER}/${GITEA_REPO}/issues/${issue_num}\" \\"
echo "    -H 'Content-Type: application/json' -u ${GITEA_USER}:${GITEA_PASS} -d '{\"state\":\"closed\"}'"
