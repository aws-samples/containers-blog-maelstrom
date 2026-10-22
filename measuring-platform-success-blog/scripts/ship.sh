#!/usr/bin/env bash
#
# ship.sh — Deploy a new version of the demo app, GitOps-style. This is the ONLY
# command you run to trigger a deployment; DevLake recording happens
# automatically via Argo Rollouts notifications (see
# 60-configure-rollout-notifications.sh).
#
# It does three things:
#   1. Edits rollout.yaml in the local dora-demo clone: sets the image tag and
#      stamps the shipped commit SHA (dora.dev/commit-sha, so DevLake can
#      compute Lead Time) plus a per-ship deploy id.
#   2. Commits and pushes that change to the dora-demo repo in Gitea.
#   3. Asks Argo CD to refresh the dora-demo Application now (instead of waiting
#      for its ~3 min poll) and waits until it has synced the pushed commit,
#      which starts a new rollout.
#
# When the rollout reaches Healthy -> notification fires result=SUCCESS.
# If you `kubectl argo rollouts abort dora-demo` instead -> result=FAILURE.
#
# Prerequisites:
#   - A clone of the Gitea dora-demo repo at ${CLONE_DIR} (default
#     /tmp/dora-demo — the one created when seeding Gitea), with 'origin'
#     pointing at Gitea.
#   - The app deployed by Argo CD (./scripts/65-deploy-demo-app.sh).
#   - Gitea reachable at ${GITEA_BASE}; a temporary port-forward is opened if not.
#
# Usage:
#   ./scripts/ship.sh <image-tag> [commit-sha]
#   ./scripts/ship.sh green                 # ships HEAD of the clone's main
#   ./scripts/ship.sh red 1a2b3c4           # explicit sha (e.g. a PR merge commit)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

APP="${APP:-dora-demo}"
IMAGE_REPO="argoproj/rollouts-demo"
CLONE_DIR="${CLONE_DIR:-/tmp/dora-demo}"
GITEA_BASE="${GITEA_BASE:-http://localhost:3000}"
SYNC_TIMEOUT="${SYNC_TIMEOUT:-120}"

TAG="${1:?usage: ship.sh <image-tag> [commit-sha]}"

# shellcheck source=lib/pf.sh
source "${SCRIPT_DIR}/lib/pf.sh"

[[ -d "${CLONE_DIR}/.git" ]] || { echo "No git clone at ${CLONE_DIR} (set CLONE_DIR)" >&2; exit 1; }

if [[ "${GITEA_BASE}" == http://localhost:3000* ]]; then
  ensure_pf "${GITEA_BASE}/api/healthz" gitea gitea-http 3000:3000
fi

# Ship from an up-to-date main (ship-pr.sh leaves the clone on its PR branch).
git -C "${CLONE_DIR}" checkout -q main
git -C "${CLONE_DIR}" pull -q --ff-only origin main

# The commit being shipped: explicit arg wins, else HEAD of main. The deploy
# commit below can't carry its own SHA, so the annotation records the change
# being shipped — which is what DevLake links to PRs for Lead Time.
SHA="${2:-$(git -C "${CLONE_DIR}" rev-parse HEAD)}"

# A unique per-ship deploy id in the POD TEMPLATE guarantees the pod-template
# hash changes on every ship, so a real rollout fires and records exactly one
# deployment even when you reship the SAME image tag (the notification's
# oncePer:currentPodHash dedupes per ship).
NONCE="$(date +%Y%m%dT%H%M%S)-${RANDOM}"
ROLLOUT_FILE="${CLONE_DIR}/rollout.yaml"

echo "==> Shipping ${IMAGE_REPO}:${TAG}  (sha=${SHA}, deploy-id=${NONCE})..."
# -i.bak + rm works with both BSD (macOS) and GNU sed.
sed -E -i.bak \
  -e "s|^( *image: )${IMAGE_REPO}:.*|\1${IMAGE_REPO}:${TAG}|" \
  -e "s|^( *dora\.dev/commit-sha: ).*|\1\"${SHA}\"|" \
  -e "s|^( *dora\.dev/deploy-id: ).*|\1\"${NONCE}\"|" \
  "${ROLLOUT_FILE}"
rm -f "${ROLLOUT_FILE}.bak"

git -C "${CLONE_DIR}" commit -q -am "deploy ${IMAGE_REPO}:${TAG} (${SHA:0:7})"
git -C "${CLONE_DIR}" push -q origin main
DEPLOY_REV="$(git -C "${CLONE_DIR}" rev-parse HEAD)"
echo "    pushed deploy commit ${DEPLOY_REV}"

echo "==> Asking Argo CD to sync ${APP}..."
kubectl -n argocd annotate application "${APP}" argocd.argoproj.io/refresh=normal --overwrite >/dev/null

deadline=$(( SECONDS + SYNC_TIMEOUT ))
# operationState is the last sync Argo CD actually applied (status.sync.revision
# moves to the new commit as soon as it's fetched, before anything is applied).
until [[ "$(kubectl -n argocd get application "${APP}" \
    -o jsonpath='{.status.operationState.syncResult.revision}/{.status.operationState.phase}' 2>/dev/null)" == "${DEPLOY_REV}/Succeeded" ]]; do
  if (( SECONDS >= deadline )); then
    echo "    Argo CD hasn't synced ${DEPLOY_REV} after ${SYNC_TIMEOUT}s:" >&2
    kubectl -n argocd get application "${APP}" -o wide >&2 || true
    exit 1
  fi
  sleep 3
done
echo "    synced."

echo ""
echo "Rollout started. Watch it:"
echo "  kubectl argo rollouts get rollout dora-demo -n dora-demo --watch"
echo ""
echo "At the 50% pause, decide:"
echo "  promote (good) -> kubectl argo rollouts promote dora-demo -n dora-demo"
echo "                    => DevLake auto-records SUCCESS when Healthy"
echo "  abort   (bad)  -> kubectl argo rollouts abort   dora-demo -n dora-demo"
echo "                    => DevLake auto-records FAILURE"
