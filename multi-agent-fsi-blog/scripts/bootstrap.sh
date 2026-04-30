#!/usr/bin/env bash
#
# End-to-end bootstrap for the blog walkthrough.
#
# 1. terraform apply cluster/        → EKS Auto Mode + Pod Identity + VPC
# 2. update kubeconfig
# 3. terraform apply bootstrap/      → ArgoCD + app-of-apps root Application
# 4. wait for ArgoCD to reconcile all addons
# 5. print credentials + next-step commands
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
  flux
  tofu-controller
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

step "Waiting for Tofu Controller to provision AgentCore (~3-5 minutes)"
# The financial-services chart's wave 0 creates a Flux Terraform CR that
# provisions Bedrock AgentCore Memory/Browser/CodeInterpreter + IAM + Pod
# Identity associations. The argocd-cm custom health check gates sync-wave
# progression on this CR reaching Ready=True, so once financial-services
# reports Synced+Healthy, AgentCore is live and the outputs Secret exists.
kubectl -n argocd wait application/financial-services \
  --for=jsonpath='{.status.sync.status}'=Synced --timeout=15m || true
kubectl -n argocd wait application/financial-services \
  --for=jsonpath='{.status.health.status}'=Healthy --timeout=15m || true
ok "financial-services Synced + Healthy"

step "Ensuring agent pods picked up AgentCore env from outputs Secret"
# Safety net: even though the custom health check now waits for the
# Terraform CR to be Ready before downstream waves run, bouncing the
# Deployments is cheap and guarantees pods don't hold stale/empty env.
if kubectl -n financial-services get secret financial-services-outputs-v1 >/dev/null 2>&1; then
  kubectl -n financial-services rollout restart \
    deploy/financial-advisor \
    deploy/portfolio-analyst \
    deploy/risk-assessment \
    deploy/market-data \
    2>/dev/null || true
  for d in financial-advisor portfolio-analyst risk-assessment market-data; do
    kubectl -n financial-services rollout status deploy/$d --timeout=5m || true
  done
  ok "Agents running with live AgentCore IDs"
else
  echo "  ! financial-services-outputs-v1 Secret missing. Inspect with:"
  echo "      kubectl describe terraform financial-services-components-v1 -n financial-services"
fi

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
   • Financial demo    : kubectl -n argocd get application financial-services
   • Jaeger UI         : kubectl port-forward -n agentgateway-system svc/jaeger 16686:16686
   • LiteLLM admin     : kubectl port-forward -n litellm svc/litellm 4000:4000

EOF
