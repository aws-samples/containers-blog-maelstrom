#!/usr/bin/env bash
#
# End-to-end bootstrap for the blog walkthrough.
#
# 1. terraform apply cluster/        → EKS Auto Mode + VPC + Pod Identity +
#                                        IAM role for the Crossplane AWS
#                                        providers (via Pod Identity on the
#                                        crossplane-system/crossplane-aws-
#                                        provider-sa ServiceAccount).
# 2. update kubeconfig
# 3. terraform apply bootstrap/      → ArgoCD + app-of-apps root Application.
# 4. wait for ArgoCD to reconcile all addons:
#    Crossplane core, Upbound AWS providers (bedrockagentcore, iam, eks),
#    Agent Gateway, agent-gateway-config, LiteLLM, financial-services.
# 5. print credentials + next-step commands.
#
# Set AWS_REGION, CLUSTER_NAME, and GITOPS_REPO_URL env vars to override
# defaults from terraform/*/variables.tf.
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(cd "${SCRIPT_DIR}/.." && pwd)"

REGION="${AWS_REGION:-us-west-2}"
CLUSTER="${CLUSTER_NAME:-finops-agents}"

ok()   { printf '\033[32m✓\033[0m %s\n' "$*"; }
step() { printf '\n\033[1;34m==>\033[0m %s\n' "$*"; }

step "Provisioning EKS Auto Mode cluster (this takes ~15 minutes)"
cd "${ROOT_DIR}/terraform/cluster"
terraform init -upgrade
terraform apply -auto-approve \
  -var "aws_region=${REGION}" \
  -var "cluster_name=${CLUSTER}"
ok "Cluster ${CLUSTER} ready in ${REGION}"

step "Updating kubeconfig"
aws eks update-kubeconfig --region "${REGION}" --name "${CLUSTER}"
kubectl get nodes
ok "kubectl context configured"

step "Installing ArgoCD + app-of-apps root"
cd "${ROOT_DIR}/terraform/bootstrap"
terraform init -upgrade
terraform apply -auto-approve \
  -var "aws_region=${REGION}" \
  -var "cluster_name=${CLUSTER}" \
  ${GITOPS_REPO_URL:+-var "gitops_repo_url=${GITOPS_REPO_URL}"}
ok "ArgoCD installed and root Application applied"

step "Waiting for ArgoCD Application controller to be ready"
kubectl -n argocd rollout status statefulset/argocd-application-controller --timeout=5m
ok "ArgoCD ready"

step "Waiting for addon Applications to sync (up to 15 minutes)"
APPS=(
  agentgateway-crds
  gateway-api-crds
  auto-mode-defaults
  crossplane-core
  crossplane-providers
  crossplane-provider-config
  crossplane-compositions
  agent-gateway
  agent-gateway-config
  litellm
)
for app in "${APPS[@]}"; do
  echo "  - waiting on ${app}"
  kubectl -n argocd wait application/"${app}" \
    --for=jsonpath='{.status.sync.status}'=Synced --timeout=10m || true
  kubectl -n argocd wait application/"${app}" \
    --for=jsonpath='{.status.health.status}'=Healthy --timeout=10m || true
done
ok "Platform addons synced"

step "Waiting for Upbound AWS providers to become Healthy"
# The three Providers pull their packages from xpkg.upbound.io and install
# their CRDs dynamically. The financial-services chart depends on those
# CRDs (Memory / Browser / CodeInterpreter / Role / RolePolicy /
# PodIdentityAssociation), so we can't move on until they're up.
for provider in provider-family-aws provider-aws-bedrockagentcore provider-aws-iam provider-aws-eks; do
  echo "  - waiting on Provider/${provider}"
  kubectl wait provider.pkg.crossplane.io/${provider} \
    --for=condition=Healthy --timeout=10m || true
done
ok "Crossplane providers Healthy"

step "Waiting for financial-services + per-agent Crossplane resources"
# Every agent with an agentcore.* toggle gets an AgentCoreMemory /
# AgentCoreBrowser / AgentCoreCodeInterpreter Claim. The Composition
# provisions the underlying Upbound MR and publishes id/arn/name into
# the <agent>-<kind>-outputs connection Secret that agent pods read.
kubectl -n argocd wait application/financial-services \
  --for=jsonpath='{.status.sync.status}'=Synced --timeout=15m || true
# Wait on the Claim Ready conditions. Ready on a Claim flips True once
# the underlying MR is Ready AND connection details have been published.
for kind in agentcorememories agentcorebrowsers agentcorecodeinterpreters; do
  for claim in $(kubectl -n financial-services get ${kind}.fsi.aws.example.com -o name 2>/dev/null); do
    echo "  - waiting on ${claim}"
    kubectl -n financial-services wait ${claim} \
      --for=condition=Ready --timeout=10m || true
  done
done
# IAM + Pod Identity resources are still raw MRs (cluster-scoped kinds
# Upbound provides), wait on those too.
for kind in roles rolepolicies podidentityassociations; do
  for mr in $(kubectl get ${kind}.aws.upbound.io -o name 2>/dev/null); do
    echo "  - waiting on ${mr}"
    kubectl wait ${mr} \
      --for=condition=Ready --timeout=10m || true
  done
done
ok "financial-services AgentCore provisioned"

step "Restarting agent Deployments so they pick up live AgentCore IDs"
for d in financial-advisor portfolio-analyst risk-assessment market-data; do
  kubectl -n financial-services rollout restart deploy/${d} 2>/dev/null || true
  kubectl -n financial-services rollout status deploy/${d} --timeout=5m || true
done
ok "Agents running"

step "Bootstrap complete"
cat <<EOF

 Cluster name         : ${CLUSTER}
 Region               : ${REGION}
 ArgoCD admin password: $(kubectl -n argocd get secret argocd-initial-admin-secret \
                           -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo '<not yet available>')
 ArgoCD UI (local)    : kubectl port-forward -n argocd svc/argocd-server 8080:80

 Smoke test the advisor (JWT authn + A2A authz enforced at the gateway):
   kubectl port-forward -n agentgateway-system svc/agent-gateway-proxy 8080:8080 &
   TOKEN=\$(kubectl create token financial-advisor-sa -n financial-services \\
     --duration=1h --audience=agent-gateway)
   curl -sS -X POST http://localhost:8080/agents/financial-advisor \\
     -H "Authorization: Bearer \$TOKEN" \\
     -H "Content-Type: application/json" \\
     -d '{"task":"I have 100 AAPL and 50 GOOGL. Is my portfolio balanced for medium risk?"}' \\
     | jq -r .result

 Next steps:
   • Verify addons     : kubectl get application -n argocd
   • AgentCore MRs     : kubectl get memories,browsers,codeinterpreters -n financial-services
   • Agent IAM + PIA   : kubectl get roles,rolepolicies,podidentityassociations -n financial-services
   • Jaeger UI         : kubectl port-forward -n agentgateway-system svc/jaeger 16686:16686
   • LiteLLM admin     : kubectl port-forward -n litellm svc/litellm 4000:4000

EOF
