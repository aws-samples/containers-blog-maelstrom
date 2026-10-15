#!/usr/bin/env bash
#
# 65-deploy-demo-app.sh — Deploy the demo app via Argo CD (GitOps) instead of
# `kubectl apply`.
#
# It:
#   1. checks the dora-demo repo exists in Gitea (seed it first — README
#      section 6 / blog "Seed Gitea with the demo repo");
#   2. mints a read-only Gitea access token and stores it as an Argo CD
#      repository Secret, so Argo CD can clone the repo over the in-cluster
#      Gitea service (first run only; re-runs keep the existing Secret);
#   3. applies platform/argocd/dora-demo-app.yaml — the Application that syncs
#      the repo's manifests (Namespace, Services, Rollout) onto the cluster;
#   4. waits for the Application to report Synced + Healthy.
#
# After this, every manifest change pushed to the repo's main branch is synced
# automatically — including the image bumps ./scripts/ship.sh commits.
#
# Prerequisites: scripts 10 (Argo CD), 30 (Gitea), 40 (Argo Rollouts) and a
# seeded dora-demo repo. Requires kubectl, curl, jq.
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITEA_BASE="${GITEA_BASE:-http://localhost:3000}"
GITEA_USER="${GITEA_USER:-gitea_admin}"
GITEA_PASS="${GITEA_PASS:-$(kubectl -n gitea get secret gitea-admin-secret -o jsonpath='{.data.password}' | base64 -d)}"
GITEA_REPO="${GITEA_REPO:-dora-demo}"
REPO_URL="http://gitea-http.gitea.svc.cluster.local:3000/${GITEA_USER}/${GITEA_REPO}.git"
REPO_SECRET="gitea-dora-demo-repo"

# shellcheck source=lib/pf.sh
source "${ROOT_DIR}/scripts/lib/pf.sh"

for bin in kubectl curl jq; do
  command -v "$bin" >/dev/null || { echo "$bin is required" >&2; exit 1; }
done

if [[ "${GITEA_BASE}" == http://localhost:3000* ]]; then
  ensure_pf "${GITEA_BASE}/api/healthz" gitea gitea-http 3000:3000
fi

echo "==> Checking ${GITEA_USER}/${GITEA_REPO} exists in Gitea..."
if ! curl -sS -f -u "${GITEA_USER}:${GITEA_PASS}" \
    "${GITEA_BASE}/api/v1/repos/${GITEA_USER}/${GITEA_REPO}" >/dev/null; then
  echo "    Repo not found. Seed Gitea first (README section 6), then re-run." >&2
  exit 1
fi

if kubectl -n argocd get secret "${REPO_SECRET}" >/dev/null 2>&1; then
  echo "==> Argo CD repository Secret ${REPO_SECRET} already exists — reusing it."
else
  echo "==> Creating a read-only Gitea token for Argo CD..."
  token=$(curl -sS -f -X POST -u "${GITEA_USER}:${GITEA_PASS}" \
    -H 'Content-Type: application/json' \
    "${GITEA_BASE}/api/v1/users/${GITEA_USER}/tokens" \
    -d "{\"name\":\"argocd-$(date +%s)\",\"scopes\":[\"read:repository\"]}" \
    | jq -r '.sha1 // empty')
  [[ -n "${token}" ]] || { echo "    Failed to create a Gitea token." >&2; exit 1; }

  echo "==> Registering the repo with Argo CD..."
  # Argo CD picks up any Secret labelled secret-type=repository as a repo.
  kubectl -n argocd create secret generic "${REPO_SECRET}" \
    --from-literal=type=git \
    --from-literal=url="${REPO_URL}" \
    --from-literal=username="${GITEA_USER}" \
    --from-literal=password="${token}" \
    --dry-run=client -o yaml \
    | kubectl label --local -f - argocd.argoproj.io/secret-type=repository -o yaml \
    | kubectl apply -f -
fi

echo "==> Applying the dora-demo Argo CD Application..."
kubectl apply -f "${ROOT_DIR}/platform/argocd/dora-demo-app.yaml"

echo "==> Waiting for Argo CD to sync the app (up to 300s)..."
deadline=$(( SECONDS + 300 ))
until [[ "$(kubectl -n argocd get application dora-demo \
    -o jsonpath='{.status.sync.status}/{.status.health.status}' 2>/dev/null)" == "Synced/Healthy" ]]; do
  if (( SECONDS >= deadline )); then
    echo "    Timed out. Current state:" >&2
    kubectl -n argocd get application dora-demo -o wide >&2 || true
    exit 1
  fi
  sleep 5
done

echo ""
echo "Demo app deployed by Argo CD (Synced/Healthy)."
echo "  kubectl -n argocd get application dora-demo"
echo "  kubectl argo rollouts get rollout dora-demo -n dora-demo --watch"
echo ""
echo "Next: ./scripts/ship.sh green"
