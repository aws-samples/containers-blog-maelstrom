#!/usr/bin/env bash
#
# ship.sh — Deploy a new version of the demo app. This is the ONLY command you
# run to trigger a deployment; DevLake recording happens automatically via Argo
# Rollouts notifications (see 60-configure-rollout-notifications.sh).
#
# It does two things:
#   1. Stamps the current Gitea commit SHA onto the Rollout's
#      dora.dev/commit-sha annotation (so DevLake can compute Lead Time).
#   2. Sets the container image, which starts a new rollout.
#
# When the rollout reaches Healthy -> notification fires result=SUCCESS.
# If you `kubectl argo rollouts abort dora-demo` instead -> result=FAILURE.
#
# Usage:
#   ./scripts/ship.sh <image-tag> [commit-sha]
#   ./scripts/ship.sh green                 # uses HEAD of ./dora-demo if present
#   ./scripts/ship.sh red 1a2b3c4           # explicit sha
#
set -euo pipefail

NS="dora-demo"
ROLLOUT="dora-demo"
CONTAINER="dora-demo"
IMAGE_REPO="argoproj/rollouts-demo"

TAG="${1:?usage: ship.sh <image-tag> [commit-sha]}"

# Resolve the commit sha: explicit arg wins, else HEAD of a local dora-demo
# clone, else "unknown".
if [[ -n "${2:-}" ]]; then
  SHA="$2"
elif git -C dora-demo rev-parse HEAD >/dev/null 2>&1; then
  SHA="$(git -C dora-demo rev-parse HEAD)"
else
  SHA="unknown"
  echo "WARN: no commit sha found; Lead Time won't be computable for this deploy." >&2
fi

# Stamp the commit SHA and a unique per-ship deploy id into the POD TEMPLATE
# (not the Rollout metadata), together with the image, in ONE atomic patch.
# Why the pod template: Argo Rollouts only starts a new revision when the pod
# template changes. Because the deploy id is unique every run, every ship.sh
# changes the pod-template hash — so a real rollout fires and records exactly
# one deployment even when you reship the SAME image tag, and the notification's
# oncePer:currentPodHash dedupes per ship without you having to think about it.
# One patch = one template change = one revision (avoids double-recording).
NONCE="$(date +%Y%m%dT%H%M%S)-${RANDOM}"
echo "==> Shipping ${IMAGE_REPO}:${TAG}  (sha=${SHA}, deploy-id=${NONCE})..."
kubectl -n "${NS}" patch rollout "${ROLLOUT}" --type=json -p "[
  {\"op\": \"replace\", \"path\": \"/spec/template/spec/containers/0/image\", \"value\": \"${IMAGE_REPO}:${TAG}\"},
  {\"op\": \"add\", \"path\": \"/spec/template/metadata/annotations\", \"value\": {\"dora.dev/commit-sha\": \"${SHA}\", \"dora.dev/deploy-id\": \"${NONCE}\"}}
]"

echo ""
echo "Rollout started. Watch it:"
echo "  kubectl argo rollouts get rollout ${ROLLOUT} -n ${NS} --watch"
echo ""
echo "At the 50% pause, decide:"
echo "  promote (good) -> kubectl argo rollouts promote ${ROLLOUT} -n ${NS}"
echo "                    => DevLake auto-records SUCCESS when Healthy"
echo "  abort   (bad)  -> kubectl argo rollouts abort   ${ROLLOUT} -n ${NS}"
echo "                    => DevLake auto-records FAILURE"
