#!/usr/bin/env bash
#
# install-platform.sh — One-shot installer for the entire DORA-on-EKS platform.
#
# Runs every setup script in order — cluster, tools, Gitea seed, DevLake wiring,
# and the Argo CD deploy of the demo app — printing a stage banner + timing for
# each. When it finishes, the browser tunnels are open and every login is
# printed, so you can go straight to looking around (or run
# ./scripts/generate-demo-data.sh to populate the DORA dashboards).
# Total wall-clock ~30 minutes (dominated by cluster creation).
#
# Every stage is safe to re-run, so after a mid-way failure just run this again.
#
# Stages, in order:
#   00-create-cluster.sh                     # EKS cluster + gp3 default StorageClass  (~15-20 min)
#   10-install-argocd.sh                     # Argo CD (GitOps for the demo app)        (~2 min)
#   20-install-argo-workflows-events.sh      # Argo Workflows + Argo Events             (~2 min)
#   30-install-gitea.sh                      # Self-hosted Gitea (Git server)           (~1 min)
#   35-seed-gitea.sh                         # dora-demo repo + local clone             (<1 min)
#   40-install-argo-rollouts.sh              # Argo Rollouts controller                 (~1 min)
#   50-install-devlake.sh                    # Apache DevLake + MySQL + Grafana         (~3-4 min)
#   52-setup-devlake-project.sh              # DevLake project + webhook connection     (~1 min)
#   55-configure-gitea-webhooks.sh           # Gitea issue/PR webhooks -> DevLake       (~1 min)
#   60-configure-rollout-notifications.sh    # auto-record deployments to DevLake       (<1 min)
#   65-deploy-demo-app.sh                    # Argo CD Application for the demo app     (~1 min)
#
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

STAGES=(
  "00-create-cluster.sh|EKS cluster (EKS Auto Mode)|~15-20 min"
  "10-install-argocd.sh|Argo CD|~2 min"
  "20-install-argo-workflows-events.sh|Argo Workflows + Argo Events|~2 min"
  "30-install-gitea.sh|Gitea (self-hosted Git)|~1 min"
  "35-seed-gitea.sh|Seed Gitea with the demo repo|<1 min"
  "40-install-argo-rollouts.sh|Argo Rollouts controller|~1 min"
  "50-install-devlake.sh|Apache DevLake + MySQL + Grafana|~3-4 min"
  "52-setup-devlake-project.sh|DevLake project + webhook connection|~1 min"
  "55-configure-gitea-webhooks.sh|Gitea issue/PR webhooks -> DevLake|~1 min"
  "60-configure-rollout-notifications.sh|Automatic deployment recording|<1 min"
  "65-deploy-demo-app.sh|Deploy the demo app with Argo CD|~1 min"
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

# Open the browser tunnels (they keep running after this script exits) and print
# every login so the UIs are ready to explore.
"${SCRIPT_DIR}/port-forward.sh" start
echo ""
"${SCRIPT_DIR}/get-credentials.sh"

cat <<'EOF'

Next steps:

  Populate the DORA dashboards (deploys, a PR, an incident, metrics):

       ./scripts/generate-demo-data.sh

  Or drive each metric by hand: ./scripts/ship.sh <tag>, ship-pr.sh,
  ship-with-incident.sh, then ./scripts/70-calculate-metrics.sh.

  Stop the tunnels when done: ./scripts/port-forward.sh stop
EOF
