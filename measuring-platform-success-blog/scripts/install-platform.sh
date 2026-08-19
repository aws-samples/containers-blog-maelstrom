#!/usr/bin/env bash
#
# install-platform.sh — One-shot installer for the entire DORA-on-EKS platform.
#
# Runs the numbered install scripts in order and prints a stage banner + timing
# for each one, so the blog walkthrough can present the whole thing as a single
# step. Total wall-clock ~25 minutes (dominated by cluster creation).
#
# Stages, in order:
#   00-create-cluster.sh                 # EKS cluster + gp3 default StorageClass  (~15-20 min)
#   10-install-argocd.sh                 # Argo CD + kro                            (~2 min)
#   20-install-argo-workflows-events.sh  # Argo Workflows + Argo Events             (~2 min)
#   30-install-gitea.sh                  # Self-hosted Gitea (Git server)           (~1 min)
#   40-install-argo-rollouts.sh          # Argo Rollouts controller                 (~1 min)
#   50-install-devlake.sh                # Apache DevLake + MySQL + Grafana         (~3-4 min)
#
# After this finishes, seed Gitea (blog Section "Seed Gitea"), then run:
#   ./scripts/52-setup-devlake-project.sh
#   ./scripts/55-configure-gitea-webhooks.sh
#   ./scripts/60-configure-rollout-notifications.sh
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STAGES=(
  "00-create-cluster.sh|EKS cluster (EKS Auto Mode)|~15-20 min"
  "10-install-argocd.sh|Argo CD + kro|~2 min"
  "20-install-argo-workflows-events.sh|Argo Workflows + Argo Events|~2 min"
  "30-install-gitea.sh|Gitea (self-hosted Git)|~1 min"
  "40-install-argo-rollouts.sh|Argo Rollouts controller|~1 min"
  "50-install-devlake.sh|Apache DevLake + MySQL + Grafana|~3-4 min"
)

banner() {
  printf '\n============================================================\n'
  printf '  %s\n' "$1"
  printf '============================================================\n\n'
}

overall_start=$(date +%s)

for stage in "${STAGES[@]}"; do
  IFS='|' read -r script label eta <<<"$stage"
  banner ">> ${label}  (est. ${eta})"
  stage_start=$(date +%s)
  "${SCRIPT_DIR}/${script}"
  stage_end=$(date +%s)
  printf '\n<< %s complete in %ds\n' "${label}" "$((stage_end - stage_start))"
done

overall_end=$(date +%s)
total=$((overall_end - overall_start))
printf '\n============================================================\n'
printf '  Platform install complete in %dm %ds\n' "$((total / 60))" "$((total % 60))"
printf '============================================================\n\n'

cat <<'EOF'
Next steps:

  1. (Optional) open the browser UIs (Gitea / DevLake config-ui / Grafana):

       ./scripts/port-forward.sh          # ...port-forward.sh stop when done

  2. Seed Gitea with the demo repo (blog Section "Seed Gitea with the
     demo repo") so DevLake has commits to compute Lead Time from.

  3. Wire DevLake up to the platform. Scripts 52/55 auto-open a temporary
     port-forward if one isn't already running, so no manual port-forwards
     are required:

       ./scripts/52-setup-devlake-project.sh
       ./scripts/55-configure-gitea-webhooks.sh

       export DEVLAKE_WEBHOOK_URL="http://devlake-ui.devlake.svc.cluster.local:4000/api/rest/plugins/webhook/connections/1/deployments"
       ./scripts/60-configure-rollout-notifications.sh

  4. Ship a version with ./scripts/ship.sh <tag> to start recording
     DORA metrics.
EOF
