# shellcheck shell=bash
#
# pf.sh — sourced helper that lets a script auto-manage its own kubectl
# port-forward for the duration of the run, so callers don't have to start one
# in a separate terminal (or clean it up afterwards).
#
# Usage (from another script):
#
#   source "$(dirname "${BASH_SOURCE[0]}")/lib/pf.sh"
#   ensure_pf "http://localhost:8080/ping" devlake devlake-lake 8080:8080
#
# If the health URL is already reachable (e.g. you started a long-lived
# port-forward yourself, or ran ./scripts/port-forward.sh), ensure_pf does
# nothing and reuses it. Otherwise it starts a background port-forward, waits
# for it to come up, and registers an EXIT trap so it's torn down when the
# script finishes — success or failure.
#
# Requires: kubectl, curl. Meant to be sourced from a `set -euo pipefail` script.

# PIDs of port-forwards this script started (so we only kill our own).
_PF_PIDS=()

_pf_cleanup() {
  local pid
  for pid in "${_PF_PIDS[@]:-}"; do
    [[ -n "${pid}" ]] && kill "${pid}" >/dev/null 2>&1 || true
  done
}
# Chain onto any existing EXIT trap rather than clobbering it.
trap _pf_cleanup EXIT

# _pf_reachable <url> — 0 if curl gets ANY HTTP response (even 4xx), non-zero
# if the connection is refused / times out. Deliberately not using -f so a
# service that answers with a non-2xx on the probe path still counts as "up".
_pf_reachable() {
  curl -sS -o /dev/null --max-time 3 "$1" >/dev/null 2>&1
}

# ensure_pf <health_url> <namespace> <service> <local:remote> [timeout_secs]
#
# Guarantees <health_url> is reachable, starting an ephemeral port-forward if
# needed. Returns non-zero (and leaves the trap to clean up) if it can't.
ensure_pf() {
  local url="$1" ns="$2" svc="$3" ports="$4" timeout="${5:-30}"

  if _pf_reachable "${url}"; then
    return 0
  fi

  echo "==> ${url} not reachable — starting a temporary port-forward" \
       "(${ns}/${svc} ${ports}); it will be closed when this script exits."
  kubectl -n "${ns}" port-forward "svc/${svc}" "${ports}" >/dev/null 2>&1 &
  _PF_PIDS+=("$!")

  local i
  for (( i = 0; i < timeout; i++ )); do
    if _pf_reachable "${url}"; then
      echo "    port-forward ready."
      return 0
    fi
    sleep 1
  done

  echo "    Timed out after ${timeout}s waiting for ${url} via port-forward." >&2
  echo "    Is ${ns}/${svc} installed and running? (kubectl -n ${ns} get pods)" >&2
  return 1
}
