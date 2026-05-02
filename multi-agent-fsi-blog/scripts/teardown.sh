#!/usr/bin/env bash
#
# Ordered teardown for the blog walkthrough. Reverses bootstrap.sh:
#
# 1. Pause ArgoCD auto-sync on financial-services so selfHeal can't
#    recreate what we delete.
# 2. Delete the Crossplane Claims + direct MRs in financial-services.
#    Claims cascade to XRs -> MRs -> real AWS AgentCore / IAM / Pod
#    Identity resources. deletionPolicy: Delete is set on every MR.
# 3. Delete the per-addon ArgoCD Applications in dependency order so
#    Crossplane is still up while earlier apps clean themselves out.
# 4. terraform destroy bootstrap/  -> ArgoCD + platform-root
# 5. terraform destroy cluster/    -> EKS Auto Mode + VPC + IAM + PIAs
#    for crossplane-aws-provider-sa and litellm
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

wait_gone() {
  # wait_gone <kind> <namespace-or-empty> <timeout-seconds>
  local kind="$1" ns="$2" timeout="$3" elapsed=0
  local ns_flag=""
  [[ -n "$ns" ]] && ns_flag="-n $ns"
  while true; do
    local count
    count=$(kubectl $ns_flag get "$kind" --no-headers 2>/dev/null | wc -l | tr -d ' ')
    if [[ "$count" == "0" ]]; then
      return 0
    fi
    if (( elapsed >= timeout )); then
      warn "timeout waiting for $kind to be deleted ($count remaining)"
      kubectl $ns_flag get "$kind" 2>/dev/null || true
      return 1
    fi
    sleep 10
    elapsed=$((elapsed + 10))
  done
}

# ---------------------------------------------------------------------------
# Phase 1: in-cluster cleanup — only runs if the cluster is still reachable.
# ---------------------------------------------------------------------------
if cluster_reachable; then
  step "Pausing ArgoCD auto-sync on financial-services + crossplane-compositions"
  # Without this, selfHeal re-creates the claims we're about to delete.
  for app in financial-services crossplane-compositions crossplane-provider-config; do
    kubectl -n argocd patch application/"${app}" --type=merge \
      -p '{"spec":{"syncPolicy":{"automated":null}}}' 2>/dev/null || true
  done
  ok "auto-sync paused"

  step "Deleting Crossplane Claims in financial-services (cascades to AgentCore AWS resources)"
  # Claims -> XRs -> Memory/Browser/CodeInterpreter MRs -> real AWS.
  # Allow up to 10 minutes per kind for the AgentCore APIs to respond.
  kubectl -n financial-services delete agentcorememory,agentcorebrowser,agentcorecodeinterpreter --all --ignore-not-found=true --wait=false
  wait_gone agentcorememory.fsi.aws.example.com      financial-services 600 || true
  wait_gone agentcorebrowser.fsi.aws.example.com     financial-services 600 || true
  wait_gone agentcorecodeinterpreter.fsi.aws.example.com financial-services 600 || true
  # XRs should be gone with their Claims, but make sure.
  kubectl delete xagentcorememory.fsi.aws.example.com,xagentcorebrowser.fsi.aws.example.com,xagentcorecodeinterpreter.fsi.aws.example.com --all --ignore-not-found=true --wait=false 2>/dev/null || true
  ok "AgentCore claims deleted"

  step "Deleting per-agent IAM + Pod Identity MRs"
  # These are direct Upbound MRs (not wrapped in Compositions). Order
  # matters a little — PIA before Role so the Role isn't gone before
  # AWS updates the association.
  kubectl delete podidentityassociation.eks.aws.upbound.io --all --ignore-not-found=true --wait=false 2>/dev/null || true
  wait_gone podidentityassociation.eks.aws.upbound.io "" 300 || true
  kubectl delete rolepolicy.iam.aws.upbound.io --all --ignore-not-found=true --wait=false 2>/dev/null || true
  wait_gone rolepolicy.iam.aws.upbound.io "" 300 || true
  kubectl delete role.iam.aws.upbound.io --all --ignore-not-found=true --wait=false 2>/dev/null || true
  wait_gone role.iam.aws.upbound.io "" 300 || true
  ok "IAM + Pod Identity MRs deleted"

  step "Deleting addon ArgoCD Applications"
  # Delete in reverse dependency order. financial-services first (already
  # drained above), then compositions/providers, then core.
  #
  # Strip the resources-finalizer.argocd.argoproj.io BEFORE the delete.
  # That finalizer tells the ArgoCD controller to prune the Application's
  # rendered manifests first — but we've already cleaned up the things
  # that matter (AgentCore / IAM / Pod Identity via Crossplane above),
  # and the cluster terraform will wipe the rest. If we leave the
  # finalizer in place, the Apps can sit in Terminating forever after
  # terraform destroys the ArgoCD helm release on the next step — the
  # controller that processes the finalizer is gone, and the argocd
  # namespace won't terminate until every Application does.
  for app in \
    financial-services \
    crossplane-compositions \
    crossplane-provider-config \
    crossplane-providers \
    crossplane-core \
    agent-gateway-config \
    agent-gateway \
    litellm \
    auto-mode-defaults \
    agentgateway-crds \
    gateway-api-crds \
  ; do
    kubectl -n argocd patch application/"${app}" --type=merge \
      -p '{"metadata":{"finalizers":null}}' 2>/dev/null || true
    kubectl -n argocd delete application/"${app}" --ignore-not-found=true --wait=false 2>/dev/null || true
  done
  wait_gone application.argoproj.io argocd 120 || true
  ok "ArgoCD applications deleted"
else
  warn "cluster not reachable — skipping in-cluster cleanup"
  warn "any orphaned AgentCore / IAM / PodIdentityAssociation resources in AWS will need manual cleanup"
fi

# ---------------------------------------------------------------------------
# Phase 2: terraform destroy bootstrap (ArgoCD + platform-root).
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

 Worth spot-checking in AWS (these are resources Crossplane created
 that could orphan if the in-cluster cleanup didn't complete):

   aws bedrock-agentcore-control list-memories         --region ${REGION}
   aws bedrock-agentcore-control list-browsers         --region ${REGION}
   aws bedrock-agentcore-control list-code-interpreters --region ${REGION}
   aws iam list-roles --query 'Roles[?starts_with(RoleName,\`fs-\`)].RoleName'
   aws eks list-pod-identity-associations --cluster-name ${CLUSTER} --region ${REGION} 2>/dev/null || true

EOF
