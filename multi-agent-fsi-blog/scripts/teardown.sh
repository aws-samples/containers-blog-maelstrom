#!/usr/bin/env bash
#
# Ordered teardown for the blog walkthrough.
#
# Strategy: let ArgoCD do the work. Each Application has
# resources-finalizer.argocd.argoproj.io — deleting the Application
# triggers cascade-prune of every resource it rendered, in reverse
# sync-wave order within the app. We do the same across apps: delete
# financial-services first, wait for ArgoCD to prune its agents +
# AgentCoreMemory/Browser/CodeInterpreter claims + the ACK Memory/Browser/
# CodeInterpreter/Role/PodIdentityAssociation resources they compose (ACK
# deletes the real AWS resource when its CR is removed), then move to the
# next Application in reverse root sync-wave order.
#
# Per-app timeout with a finalizer-strip fallback — if cascade-prune
# stalls on one Application we strip its finalizer and continue, so a
# single stuck App doesn't hang the whole teardown. Stripped Apps log a
# warning; the AWS spot-check block at the end surfaces any orphans.
#
# Phases:
#   1. Pause ArgoCD auto-sync so selfHeal can't recreate resources mid-prune.
#   2. Delete every child Application in reverse sync-wave order, then
#      platform-root.
#   3. terraform destroy bootstrap/  -> ArgoCD + platform-root Application.
#   4. terraform destroy cluster/    -> EKS Auto Mode + VPC + IAM + PIAs.
#
# Set AWS_REGION and CLUSTER_NAME env vars to override defaults.
set -uo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

REGION="${AWS_REGION:-us-west-2}"
CLUSTER="${CLUSTER_NAME:-finops-agents}"

ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '\033[33m!\033[0m %s\n' "$*"; }
step() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

cluster_reachable() {
  kubectl get ns argocd >/dev/null 2>&1
}

# delete_app <name> <timeout-seconds>
#
# Trigger cascade-prune by deleting the Application, then poll until the
# Application object is gone. If the timeout elapses we strip the
# finalizer and force the deletion through — this leaves any still-
# pending child MRs orphaned, which the AWS spot-check surfaces.
delete_app() {
  local app="$1" timeout="$2" elapsed=0
  kubectl -n argocd get application/"$app" >/dev/null 2>&1 || { ok "$app not present"; return 0; }

  kubectl -n argocd delete application/"$app" --ignore-not-found=true --wait=false >/dev/null 2>&1 || true

  while kubectl -n argocd get application/"$app" >/dev/null 2>&1; do
    if (( elapsed >= timeout )); then
      warn "cascade-prune on $app didn't finish in ${timeout}s — stripping finalizer"
      kubectl -n argocd patch application/"$app" --type=merge \
        -p '{"metadata":{"finalizers":null}}' >/dev/null 2>&1 || true
      # Brief settle so the apiserver processes the patch before we
      # check again; if the object is still there, force a second delete.
      sleep 5
      kubectl -n argocd delete application/"$app" --ignore-not-found=true >/dev/null 2>&1 || true
      return 0
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done
  ok "$app drained"
}

# ---------------------------------------------------------------------------
# Phase 1: in-cluster cleanup via ArgoCD cascade — only if reachable.
# ---------------------------------------------------------------------------
if cluster_reachable; then
  step "Pausing ArgoCD auto-sync on every Application"
  # Without this, selfHeal re-creates resources faster than we can prune.
  for app in $(kubectl -n argocd get application -o name 2>/dev/null); do
    kubectl -n argocd patch "$app" --type=merge \
      -p '{"spec":{"syncPolicy":{"automated":null}}}' >/dev/null 2>&1 || true
  done
  ok "auto-sync paused"

  step "Deleting Applications in reverse sync-wave order"
  # Order: wave 5 -> 3 -> 2 -> 1 -> 0 -> -1, then platform-root.
  # Timeouts account for AgentCore async deletes, IAM eventual consistency,
  # and agent pod termination grace periods.
  delete_app financial-services          600   # agents + claims -> ACK CRs -> AWS
  delete_app litellm                     180   # Deployment + Postgres PVC
  delete_app agent-gateway-config        120   # Gateway + JWT/RBAC policies
  delete_app agent-gateway               180   # Gateway controller + service
  delete_app agentcore-rgds              180   # kro ResourceGraphDefinitions (no external state)
  # ACK controllers last (after the ACK CRs they reconcile are gone), so their
  # finalizers can complete the AWS-side deletes before the controllers stop.
  delete_app ack-bedrockagentcorecontrol 300   # AgentCore Memory/Browser/CodeInterpreter controller
  delete_app ack-iam                     300   # IAM Role/Policy controller
  delete_app ack-eks                     300   # PodIdentityAssociation controller
  delete_app auto-mode-defaults          120   # StorageClass + IngressClass
  delete_app agentgateway-crds           120
  delete_app gateway-api-crds            120
  delete_app platform-root               60    # root app-of-apps
  ok "all Applications deleted"
else
  warn "cluster not reachable — skipping in-cluster cleanup"
  warn "any orphaned AgentCore / IAM / PodIdentityAssociation resources in AWS will need manual cleanup"
fi

# ---------------------------------------------------------------------------
# Phase 2: terraform destroy bootstrap (ArgoCD helm release + platform-root).
# ---------------------------------------------------------------------------
step "terraform destroy — bootstrap/"
cd "${ROOT_DIR}/terraform/bootstrap"
terraform init -upgrade
terraform destroy -auto-approve \
  -var "aws_region=${REGION}" \
  -var "cluster_name=${CLUSTER}" \
  ${GITOPS_REPO_URL:+-var "gitops_repo_url=${GITOPS_REPO_URL}"} || warn "bootstrap destroy reported errors"
ok "bootstrap torn down"

# ---------------------------------------------------------------------------
# Phase 3: terraform destroy cluster (EKS + VPC + IAM + PIAs).
# ---------------------------------------------------------------------------
step "terraform destroy — cluster/ (this takes ~15 minutes)"
cd "${ROOT_DIR}/terraform/cluster"
terraform init -upgrade
terraform destroy -auto-approve \
  -var "aws_region=${REGION}" \
  -var "cluster_name=${CLUSTER}" || warn "cluster destroy reported errors"
ok "cluster torn down"

step "Teardown complete"
cat <<EOF

 Cluster ${CLUSTER} in ${REGION} is gone.

 Spot-check AWS for orphan resources. If the teardown hit any
 'cascade-prune ... didn't finish' warnings above, expect entries here
 and clean them up by hand.

   aws bedrock-agentcore-control list-memories         --region ${REGION}
   aws bedrock-agentcore-control list-browsers         --region ${REGION}
   aws bedrock-agentcore-control list-code-interpreters --region ${REGION}
   aws iam list-roles --query 'Roles[?starts_with(RoleName,\`fs-\`)].RoleName'
   aws eks list-pod-identity-associations --cluster-name ${CLUSTER} --region ${REGION} 2>/dev/null || true

EOF
