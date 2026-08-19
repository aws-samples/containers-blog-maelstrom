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

WORKFLOWS_VERSION="${WORKFLOWS_VERSION:-v3.6.2}"
EVENTS_VERSION="${EVENTS_VERSION:-v1.9.3}"

echo "==> Installing Argo Workflows (${WORKFLOWS_VERSION})..."
kubectl create namespace argo --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo \
  -f "https://github.com/argoproj/argo-workflows/releases/download/${WORKFLOWS_VERSION}/quick-start-minimal.yaml"

echo "==> Installing Argo Events (${EVENTS_VERSION})..."
kubectl create namespace argo-events --dry-run=client -o yaml | kubectl apply -f -
kubectl apply -n argo-events \
  -f "https://raw.githubusercontent.com/argoproj/argo-events/${EVENTS_VERSION}/manifests/install.yaml"
# EventBus backend (NATS) — required for Sensors/EventSources to function.
kubectl apply -n argo-events \
  -f "https://raw.githubusercontent.com/argoproj/argo-events/${EVENTS_VERSION}/examples/eventbus/native.yaml"

echo "==> Waiting for controllers to become ready..."
kubectl -n argo rollout status deploy/workflow-controller --timeout=300s || true
kubectl -n argo-events rollout status deploy/controller-manager --timeout=300s || true

echo ""
echo "Argo Workflows UI:"
echo "  kubectl -n argo port-forward svc/argo-server 2746:2746"
echo "  open https://localhost:2746"
echo ""
echo "Next: ./scripts/30-install-gitea.sh"
