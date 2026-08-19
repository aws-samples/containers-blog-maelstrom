#!/usr/bin/env bash
#
# port-forward.sh — open (or close) the browser-facing port-forwards for the
# demo in one shot, so you don't have to juggle several `kubectl port-forward &`
# commands across terminals.
#
# The numbered setup scripts (52/55/70) manage their OWN short-lived tunnels via
# scripts/lib/pf.sh, so you only need this for the interactive UIs you open in a
# browser (Gitea, DevLake config-ui, Grafana). Starting the lake tunnel here too
# is handy — the setup scripts will simply reuse it instead of opening their own.
#
# Usage:
#   ./scripts/port-forward.sh [start]   # start all tunnels in the background
#   ./scripts/port-forward.sh status    # show which tunnels are up
#   ./scripts/port-forward.sh stop      # stop the tunnels this script started
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
PID_FILE="${ROOT_DIR}/.port-forward.pids"

# label | namespace | service | local:remote | browser URL
TUNNELS=(
  "Gitea|gitea|gitea-http|3000:3000|http://localhost:3000  (gitea_admin / gitea_admin_pass)"
  "DevLake config-ui + Grafana|devlake|devlake-ui|4000:4000|http://localhost:4000  (Grafana at /grafana; user admin, pw in secret devlake-grafana)"
  "DevLake lake API|devlake|devlake-lake|8080:8080|http://localhost:8080  (used by setup scripts)"
)

start() {
  if [[ -f "${PID_FILE}" ]] && kill -0 "$(head -n1 "${PID_FILE}" 2>/dev/null | cut -d' ' -f1)" 2>/dev/null; then
    echo "Tunnels already look active (see ${PID_FILE}). Run 'stop' first to restart."
    status
    return 0
  fi
  : >"${PID_FILE}"
  echo "Starting port-forwards..."
  local entry label ns svc ports url
  for entry in "${TUNNELS[@]}"; do
    IFS='|' read -r label ns svc ports url <<<"${entry}"
    kubectl -n "${ns}" port-forward "svc/${svc}" "${ports}" >/dev/null 2>&1 &
    echo "$! ${label} ${ns}/${svc} ${ports}" >>"${PID_FILE}"
    printf '  %-28s -> %s\n' "${label}" "${url}"
  done
  echo ""
  echo "All tunnels started. Stop them with: ./scripts/port-forward.sh stop"
}

status() {
  if [[ ! -s "${PID_FILE}" ]]; then
    echo "No tunnels recorded (${PID_FILE} missing or empty)."
    return 0
  fi
  echo "Recorded tunnels:"
  local pid rest
  while read -r pid rest; do
    if kill -0 "${pid}" 2>/dev/null; then
      printf '  [up]   pid %-7s %s\n' "${pid}" "${rest}"
    else
      printf '  [down] pid %-7s %s\n' "${pid}" "${rest}"
    fi
  done <"${PID_FILE}"
}

stop() {
  if [[ ! -s "${PID_FILE}" ]]; then
    echo "Nothing to stop (${PID_FILE} missing or empty)."
    return 0
  fi
  echo "Stopping port-forwards..."
  local pid rest
  while read -r pid rest; do
    if kill "${pid}" >/dev/null 2>&1; then
      printf '  stopped pid %-7s %s\n' "${pid}" "${rest}"
    fi
  done <"${PID_FILE}"
  rm -f "${PID_FILE}"
}

case "${1:-start}" in
  start)  start ;;
  status) status ;;
  stop)   stop ;;
  *)
    echo "Usage: $0 [start|status|stop]" >&2
    exit 1
    ;;
esac
