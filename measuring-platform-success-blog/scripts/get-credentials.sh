#!/usr/bin/env bash
#
# get-credentials.sh — Print every login and generated password for the demo
# in one place, read straight from the cluster's Secrets, so you don't have to
# remember (or retype) each `kubectl get secret ... | base64 -d` command.
#
# Components that aren't installed yet are reported as "not found" rather than
# failing the script.
#
# Usage:
#   ./scripts/get-credentials.sh
#
# The output contains plaintext passwords — don't paste it anywhere shared.
#
set -euo pipefail

# secret_val <namespace> <secret> <key> — decoded value, or empty if missing.
secret_val() {
  kubectl -n "$1" get secret "$2" -o "jsonpath={.data.$3}" 2>/dev/null | base64 -d 2>/dev/null || true
}

# show <label> <value> — print a row, flagging values that couldn't be read.
show() {
  printf '  %-16s %s\n' "$1" "${2:-(not found)}"
}

echo "Argo CD          https://localhost:8443   (./scripts/port-forward.sh)"
show "username" "admin"
show "password" "$(secret_val argocd argocd-initial-admin-secret password)"
echo ""

echo "Gitea            http://localhost:3000"
show "username" "$(secret_val gitea gitea-admin-secret username)"
show "password" "$(secret_val gitea gitea-admin-secret password)"
echo ""

echo "Grafana          http://localhost:4000/grafana/"
show "username" "$(secret_val devlake devlake-grafana admin-user)"
show "password" "$(secret_val devlake devlake-grafana admin-password)"
echo ""

echo "DevLake MySQL    devlake-mysql.devlake.svc.cluster.local:3306 (in-cluster only)"
show "username" "merico"
show "password" "$(secret_val devlake devlake-mysql-auth MYSQL_PASSWORD)"
show "root password" "$(secret_val devlake devlake-mysql-auth MYSQL_ROOT_PASSWORD)"
echo ""

echo "DevLake webhook  (created by ./scripts/52-setup-devlake-project.sh)"
show "connection id" "$(kubectl -n argo get configmap devlake-webhook-id -o jsonpath='{.data.DEVLAKE_HOOK_ID}' 2>/dev/null || true)"
show "api key" "$(secret_val argo devlake-webhook-secret DEVLAKE_TOKEN)"
