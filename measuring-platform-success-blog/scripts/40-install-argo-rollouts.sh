#!/usr/bin/env bash
#
# 40-install-argo-rollouts.sh — Install the Argo Rollouts controller + kubectl
# plugin.
#
# Argo Rollouts is the star of the DORA show: its Rollout resource gives us
# canary/blue-green deploys we can promote, abort, and roll back — exactly the
# events DevLake turns into Deployment Frequency, Change Failure Rate, and Time
# to Restore Service.
#
set -euo pipefail

# NOTE: Argo Rollouts has NO "stable" release alias (that's an Argo CD thing).
# GitHub only understands "latest" or a pinned tag, and the two use different
# URL shapes:
#   latest:      /releases/latest/download/<asset>
#   pinned tag:  /releases/download/<tag>/<asset>
ROLLOUTS_VERSION="${ROLLOUTS_VERSION:-latest}"

if [[ "${ROLLOUTS_VERSION}" == "latest" ]]; then
  ROLLOUTS_BASE="https://github.com/argoproj/argo-rollouts/releases/latest/download"
else
  ROLLOUTS_BASE="https://github.com/argoproj/argo-rollouts/releases/download/${ROLLOUTS_VERSION}"
fi

echo "==> Installing Argo Rollouts (${ROLLOUTS_VERSION})..."
kubectl create namespace argo-rollouts --dry-run=client -o yaml | kubectl apply -f -
# Server-side apply: the Rollout CRD is large enough to exceed the 262144-byte
# last-applied-configuration annotation that client-side apply writes.
kubectl apply --server-side --force-conflicts -n argo-rollouts \
  -f "${ROLLOUTS_BASE}/install.yaml"

echo "==> Waiting for the Rollouts controller..."
kubectl -n argo-rollouts rollout status deploy/argo-rollouts --timeout=300s

echo ""
echo "==> Install the kubectl-argo-rollouts plugin if you don't have it:"
echo "    macOS:  brew install argoproj/tap/kubectl-argo-rollouts"
echo "    Linux:  curl -sSL -o /usr/local/bin/kubectl-argo-rollouts \\"
echo "              ${ROLLOUTS_BASE}/kubectl-argo-rollouts-linux-amd64 \\"
echo "              && chmod +x /usr/local/bin/kubectl-argo-rollouts"
echo ""
echo "Next: ./scripts/50-install-devlake.sh"
