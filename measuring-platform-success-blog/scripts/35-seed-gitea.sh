#!/usr/bin/env bash
#
# 35-seed-gitea.sh — Create the dora-demo repo in Gitea and push this folder's
# app/ manifests to it, via a local clone at ${CLONE_DIR}.
#
# DevLake needs commit/PR history for Lead Time, Argo CD deploys the app from
# this repo, and ship.sh / ship-pr.sh commit to the same clone. Idempotent: an
# existing repo, clone, or main branch is reused as-is.
#
# Config via env vars:
#   GITEA_BASE   Gitea URL           (default: http://localhost:3000; a
#                                     temporary port-forward is opened if needed)
#   GITEA_USER   repo owner          (default: gitea_admin)
#   GITEA_REPO   repo name           (default: dora-demo)
#   CLONE_DIR    local clone         (default: /tmp/dora-demo)
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
GITEA_BASE="${GITEA_BASE:-http://localhost:3000}"
GITEA_USER="${GITEA_USER:-gitea_admin}"
GITEA_PASS="${GITEA_PASS:-$(kubectl -n gitea get secret gitea-admin-secret -o jsonpath='{.data.password}' | base64 -d)}"
GITEA_REPO="${GITEA_REPO:-dora-demo}"
CLONE_DIR="${CLONE_DIR:-/tmp/dora-demo}"

# shellcheck source=lib/pf.sh
source "${ROOT_DIR}/scripts/lib/pf.sh"

for bin in git curl kubectl; do
  command -v "$bin" >/dev/null || { echo "$bin is required" >&2; exit 1; }
done

if [[ "${GITEA_BASE}" == http://localhost:3000* ]]; then
  ensure_pf "${GITEA_BASE}/api/healthz" gitea gitea-http 3000:3000
fi

echo "==> Ensuring repo ${GITEA_USER}/${GITEA_REPO} exists in Gitea..."
if curl -sS -f -u "${GITEA_USER}:${GITEA_PASS}" \
    "${GITEA_BASE}/api/v1/repos/${GITEA_USER}/${GITEA_REPO}" >/dev/null 2>&1; then
  echo "    already exists."
else
  curl -sS -f -X POST -u "${GITEA_USER}:${GITEA_PASS}" -H 'Content-Type: application/json' \
    "${GITEA_BASE}/api/v1/user/repos" \
    -d "{\"name\":\"${GITEA_REPO}\",\"default_branch\":\"main\",\"auto_init\":false}" >/dev/null
  echo "    created."
fi

if [[ -d "${CLONE_DIR}/.git" ]]; then
  echo "==> Reusing existing clone at ${CLONE_DIR}."
else
  echo "==> Creating ${CLONE_DIR} from app/ ..."
  mkdir -p "${CLONE_DIR}"
  cp -r "${ROOT_DIR}"/app/* "${CLONE_DIR}/"
  git -C "${CLONE_DIR}" init -q -b main
  # ship.sh / ship-pr.sh commit here; give the clone an identity if none is set.
  git -C "${CLONE_DIR}" config user.name >/dev/null || git -C "${CLONE_DIR}" config user.name "DORA demo"
  git -C "${CLONE_DIR}" config user.email >/dev/null || git -C "${CLONE_DIR}" config user.email "dora-demo@example.com"
  git -C "${CLONE_DIR}" add .
  git -C "${CLONE_DIR}" commit -q -m "initial demo app"
  git -C "${CLONE_DIR}" remote add origin \
    "http://${GITEA_USER}:${GITEA_PASS}@${GITEA_BASE#http://}/${GITEA_USER}/${GITEA_REPO}.git"
fi

if [[ -n "$(git -C "${CLONE_DIR}" ls-remote --heads origin main)" ]]; then
  echo "==> Gitea already has a main branch — leaving it as-is."
else
  echo "==> Pushing main to Gitea..."
  git -C "${CLONE_DIR}" push -q -u origin main
fi

echo ""
echo "Gitea seeded: ${GITEA_USER}/${GITEA_REPO} (local clone: ${CLONE_DIR})."
