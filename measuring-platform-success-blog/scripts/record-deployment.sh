#!/usr/bin/env bash
#
# record-deployment.sh — Post a deployment event to DevLake's Incoming Webhook.
#
# DevLake can't see an Argo Rollout promotion on its own, so we tell it: every
# time you promote or abort the demo rollout, run this script. DevLake turns
# these records into the deployment-based DORA metrics:
#
#   result=SUCCESS  -> counts toward Deployment Frequency + (with commit_sha)
#                      Lead Time for Changes
#   result=FAILURE  -> counts toward Change Failure Rate
#   a FAILURE followed by a SUCCESS -> Time to Restore Service
#
# Usage:
#   ./scripts/record-deployment.sh SUCCESS <commit_sha> [environment]
#   ./scripts/record-deployment.sh FAILURE <commit_sha> [environment]
#
# Requirements:
#   - DEVLAKE_WEBHOOK_URL  full POST URL of the DevLake Incoming Webhook
#                          connection you created in the config UI, e.g.
#                          http://localhost:4000/api/rest/plugins/webhook/connections/1/deployments
#   - jq, curl
#
set -euo pipefail

RESULT="${1:?usage: record-deployment.sh <SUCCESS|FAILURE> <commit_sha> [env]}"
COMMIT_SHA="${2:?commit sha required}"
ENVIRONMENT="${3:-PRODUCTION}"

: "${DEVLAKE_WEBHOOK_URL:?set DEVLAKE_WEBHOOK_URL to your DevLake webhook deployments endpoint}"

# started/finished timestamps. For a real pipeline you'd capture the true start
# time; for the demo we approximate a short deploy window ending now.
FINISHED_AT="$(date -u +%Y-%m-%dT%H:%M:%S%z)"
STARTED_AT="$(date -u -v-2M +%Y-%m-%dT%H:%M:%S%z 2>/dev/null \
              || date -u -d '2 minutes ago' +%Y-%m-%dT%H:%M:%S%z)"

echo "==> Recording ${RESULT} deployment of ${COMMIT_SHA} to ${ENVIRONMENT}..."

curl -sS -f -X POST "${DEVLAKE_WEBHOOK_URL}" \
  -H 'Content-Type: application/json' \
  -d "$(jq -n \
        --arg result "${RESULT}" \
        --arg env "${ENVIRONMENT}" \
        --arg sha "${COMMIT_SHA}" \
        --arg started "${STARTED_AT}" \
        --arg finished "${FINISHED_AT}" \
        '{
           deploymentCommits: [
             {
               repoUrl: "http://gitea-http.gitea.svc.cluster.local:3000/gitea_admin/dora-demo.git",
               refName: "main",
               commitSha: $sha,
               startedDate: $started,
               finishedDate: $finished
             }
           ],
           result: $result,
           environment: $env,
           id: ("dora-demo-" + $sha + "-" + $finished),
           startedDate: $started,
           finishedDate: $finished
         }')"

echo ""
echo "==> Done. Give DevLake a minute, then refresh the DORA dashboard in Grafana."
