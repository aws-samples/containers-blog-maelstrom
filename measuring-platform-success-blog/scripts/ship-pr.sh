#!/usr/bin/env bash
#
# ship-pr.sh — Lead Time for Changes helper.
#
# Runs the full PR flow the LTFC metric needs, end to end:
#   branch -> commit -> open PR -> merge -> ship the PR's MERGE commit -> promote
#
# Why the merge commit: DevLake links a deployment to a pull request by matching
# the deployment's commitSha to the PR's merge_commit_sha. Shipping the branch
# tip instead would never link, and LTFC would stay empty. See the blog's
# "Lead Time for Changes" section.
#
# Prerequisites:
#   - Gitea reachable at ${GITEA_BASE} (default http://localhost:3000 — run
#     ./scripts/port-forward.sh first).
#   - A local clone of the demo repo at ${CLONE_DIR} (default /tmp/dora-demo),
#     with 'origin' pointing at the Gitea dora-demo repo.
#   - kubectl-argo-rollouts, git, curl, jq.
#
# Usage:
#   ./scripts/ship-pr.sh [image-tag]        # default tag: green
#   TAG=blue ./scripts/ship-pr.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

TAG="${1:-${TAG:-green}}"
NS="${NS:-dora-demo}"
ROLLOUT="${ROLLOUT:-dora-demo}"
CLONE_DIR="${CLONE_DIR:-/tmp/dora-demo}"
GITEA_BASE="${GITEA_BASE:-http://localhost:3000}"
GITEA_USER="${GITEA_USER:-gitea_admin}"
GITEA_PASS="${GITEA_PASS:-gitea_admin_pass}"
GITEA_REPO="${GITEA_REPO:-dora-demo}"
BRANCH="${BRANCH:-lead-time-$(date +%Y%m%d%H%M%S)}"

for bin in git curl jq kubectl; do
  command -v "$bin" >/dev/null || { echo "$bin is required" >&2; exit 1; }
done
[[ -d "${CLONE_DIR}/.git" ]] || { echo "No git clone at ${CLONE_DIR} (set CLONE_DIR)" >&2; exit 1; }

# Gitea API base with embedded creds (strip scheme off GITEA_BASE for the userinfo form).
GT="http://${GITEA_USER}:${GITEA_PASS}@${GITEA_BASE#http://}/api/v1/repos/${GITEA_USER}/${GITEA_REPO}"

echo "==> Creating branch '${BRANCH}' and pushing a change..."
git -C "${CLONE_DIR}" checkout -b "${BRANCH}"
echo "// change $(date -u +%FT%TZ)" >> "${CLONE_DIR}/services.yaml"
git -C "${CLONE_DIR}" commit -am "adjust demo service (${BRANCH})"
git -C "${CLONE_DIR}" push -u origin "${BRANCH}"

echo "==> Opening PR (${BRANCH} -> main)..."
pr_num=$(curl -sS -X POST "${GT}/pulls" -H 'Content-Type: application/json' \
  -d "{\"head\":\"${BRANCH}\",\"base\":\"main\",\"title\":\"Adjust demo service (${BRANCH})\"}" \
  | jq -r '.number // empty')
[[ -n "${pr_num}" ]] || { echo "    Failed to open PR (is base 'main' correct?)." >&2; exit 1; }
echo "    PR #${pr_num}"

# Let the "opened" webhook be delivered and processed before we merge. Gitea
# fires a pull_request event on both open and merge, keyed to the same PR in
# DevLake. If they race, the "opened" record (merged=false, mergedDate=null) can
# land last and clobber the merged one — leaving merged_date NULL so Lead Time
# won't compute. A short pause makes the merge event the last writer.
WEBHOOK_SETTLE="${WEBHOOK_SETTLE:-15}"
echo "==> Waiting ${WEBHOOK_SETTLE}s for the 'opened' webhook to settle before merging..."
sleep "${WEBHOOK_SETTLE}"

echo "==> Merging PR #${pr_num}..."
curl -sS -X POST "${GT}/pulls/${pr_num}/merge" -H 'Content-Type: application/json' \
  -d '{"Do":"merge"}' >/dev/null

merge_sha=$(curl -sS "${GT}/pulls/${pr_num}" | jq -r '.merge_commit_sha // empty')
[[ -n "${merge_sha}" ]] || { echo "    No merge_commit_sha — did the merge succeed?" >&2; exit 1; }
echo "    merge commit: ${merge_sha}"

echo "==> Shipping the merge commit (tag=${TAG})..."
"${SCRIPT_DIR}/ship.sh" "${TAG}" "${merge_sha}"

echo "==> Waiting for the rollout to reach the manual pause..."
until [[ "$(kubectl -n "${NS}" get rollout "${ROLLOUT}" -o jsonpath='{.status.phase}' 2>/dev/null)" == "Paused" ]]; do
  sleep 3
done

echo "==> Promoting to Healthy..."
kubectl argo rollouts promote "${ROLLOUT}" -n "${NS}" --full
kubectl argo rollouts status "${ROLLOUT}" -n "${NS}"

echo ""
echo "Done. PR #${pr_num} merged as ${merge_sha} and deployed."
echo "Compute metrics to see Lead Time for Changes:"
echo "  ./scripts/70-calculate-metrics.sh"
