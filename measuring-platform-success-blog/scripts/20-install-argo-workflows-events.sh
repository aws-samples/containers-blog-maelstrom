#!/usr/bin/env bash
#
# 20-install-argo-workflows-events.sh — Install Argo Workflows and Argo Events.
#
# These aren't strictly required to *measure* DORA metrics, but they round out
# the Argo platform and are useful if you later want to automate commit/deploy
# generation. Argo Rollouts (the piece that actually drives the deployment
# metrics) is installed separately in 40-install-argo-rollouts.sh.
#
set -euo pipefail

WORKFLOWS_VERSION="${WORKFLOWS_VERSION:-v4.1.4}"
EVENTS_VERSION="${EVENTS_VERSION:-v1.9.11}"

# Use server-side apply for these manifests. The Argo Workflows and Argo Events
# CRDs (workflows, cronworkflows, clusterworkflowtemplates, sensors, ...) are
# larger than 262144 bytes, which is the size limit on the
# kubectl.kubernetes.io/last-applied-configuration annotation that CLIENT-side
# apply writes — producing "metadata.annotations: Too long". Server-side apply
# doesn't store that annotation, so it sidesteps the limit entirely.
# --force-conflicts lets re-runs (and clusters where a client-side apply was
# attempted first) take ownership of fields cleanly.
APPLY=(kubectl apply --server-side --force-conflicts)

echo "==> Installing Argo Workflows (${WORKFLOWS_VERSION})..."
kubectl create namespace argo --dry-run=client -o yaml | kubectl apply -f -
"${APPLY[@]}" -n argo \
  -f "https://github.com/argoproj/argo-workflows/releases/download/${WORKFLOWS_VERSION}/install.yaml"

echo "==> Installing Argo Events (${EVENTS_VERSION})..."
kubectl create namespace argo-events --dry-run=client -o yaml | kubectl apply -f -
"${APPLY[@]}" -n argo-events \
  -f "https://raw.githubusercontent.com/argoproj/argo-events/${EVENTS_VERSION}/manifests/install.yaml"
# EventBus backend (JetStream) — required for Sensors/EventSources to function.
# See platform/argo-events/eventbus.yaml for why this isn't the upstream
# native.yaml (STAN) example.
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
kubectl apply -f "${SCRIPT_DIR}/../platform/argo-events/eventbus.yaml"

echo "==> Waiting for controllers to become ready..."
kubectl -n argo rollout status deploy/workflow-controller --timeout=300s || true
kubectl -n argo-events rollout status deploy/controller-manager --timeout=300s || true

echo ""
echo "Argo Workflows UI (optional — not needed for the walkthrough):"
echo "  kubectl -n argo port-forward svc/argo-server 2746:2746"
echo "  open https://localhost:2746  and paste a bearer token, e.g.:"
echo "    echo \"Bearer \$(kubectl -n argo create token argo-server)\""
echo ""
echo "Next: ./scripts/30-install-gitea.sh"
