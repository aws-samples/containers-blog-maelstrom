#!/usr/bin/env bash
#
# generate-demo-data.sh — Populate the DORA dashboards in one go, after
# install-platform.sh. It drives the same scripts you'd run by hand:
#
#   1. ship.sh + promote          a healthy deploy        -> Deployment Frequency
#   2. ship-pr.sh                 PR -> merge -> deploy   -> Lead Time for Changes
#   3. ship-with-incident.sh      deploy + open incident  -> Change Failure Rate
#   4. 70-calculate-metrics.sh    compute the metrics so Grafana shows them
#
# The incident from step 3 is left OPEN on purpose: close it yourself (the
# command is printed at the end) and re-run 70-calculate-metrics.sh to see Time
# to Restore Service.
#
# Takes ~5-10 minutes (each deploy walks the canary). Requires
# kubectl-argo-rollouts, git, curl, jq.
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NS="${NS:-dora-demo}"
ROLLOUT="${ROLLOUT:-dora-demo}"

banner() {
  printf '\n============================================================\n'
  printf '  %s\n' "$1"
  printf '============================================================\n\n'
}

banner "1/4  Healthy deploy (Deployment Frequency)"
"${SCRIPT_DIR}/ship.sh" blue
echo "==> Waiting for the rollout to reach the manual pause..."
until [[ "$(kubectl -n "${NS}" get rollout "${ROLLOUT}" -o jsonpath='{.status.phase}' 2>/dev/null)" == "Paused" ]]; do
  sleep 3
done
echo "==> Promoting to Healthy..."
kubectl argo rollouts promote "${ROLLOUT}" -n "${NS}" --full
kubectl argo rollouts status "${ROLLOUT}" -n "${NS}"

banner "2/4  PR -> merge -> deploy (Lead Time for Changes)"
"${SCRIPT_DIR}/ship-pr.sh" green

banner "3/4  Deploy followed by an incident (Change Failure Rate)"
"${SCRIPT_DIR}/ship-with-incident.sh" red

banner "4/4  Compute the DORA metrics"
"${SCRIPT_DIR}/70-calculate-metrics.sh"

cat <<'EOF'

Demo data generated. Open Grafana (http://localhost:4000/grafana/) -> DORA
dashboard; logins: ./scripts/get-credentials.sh

For Time to Restore Service: close the incident issue opened in step 3 (in the
Gitea UI, or with the curl command printed above), then recompute:

     ./scripts/70-calculate-metrics.sh
EOF
