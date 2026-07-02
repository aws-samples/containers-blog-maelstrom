#!/usr/bin/env bash
#
# End-to-end bootstrap for the blog walkthrough.
#
# 1. terraform apply cluster/        → EKS Auto Mode + VPC + the ACK and kro
#                                        EKS Capabilities (AWS-managed
#                                        controllers) + their IAM roles + a
#                                        LiteLLM Bedrock Pod Identity role.
# 2. update kubeconfig
# 3. terraform apply bootstrap/      → ArgoCD + app-of-apps root Application.
# 4. wait for the ACK + kro Capabilities to be ACTIVE, then for ArgoCD to
#    reconcile all addons: agentcore-rgds (kro RGDs), Agent Gateway,
#    agent-gateway-config, LiteLLM, financial-services.
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
  agentcore-rgds
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

step "Waiting for the ACK + kro EKS Capabilities to be ACTIVE"
# Both Capabilities are created by terraform/cluster (step 1), so they are
# normally ACTIVE by now. The ACK Capability installs the service controllers
# + their CRDs (bedrockagentcorecontrol / iam / eks); kro installs the
# ResourceGraphDefinition CRD. The financial-services chart depends on both, so
# confirm before moving on.
for cap in ack kro; do
  echo "  - waiting on capability/${cap}"
  for _ in $(seq 1 60); do
    state="$(aws eks describe-capability --cluster-name "${CLUSTER}" --region "${REGION}" \
      --capability-name "${cap}" --query 'capability.status' --output text 2>/dev/null || echo '')"
    [ "${state}" = "ACTIVE" ] && break
    sleep 10
  done
  echo "    ${cap}: ${state:-unknown}"
done
# The RGDs are served by kro once they reconcile. Wait for all three Active.
for rgd in agentcorememory.fsi.aws.example.com agentcorebrowser.fsi.aws.example.com agentcorecodeinterpreter.fsi.aws.example.com; do
  echo "  - waiting on resourcegraphdefinition/${rgd}"
  kubectl wait resourcegraphdefinition/${rgd} \
    --for=jsonpath='{.status.state}'=Active --timeout=5m || true
done
ok "ACK + kro Capabilities and RGDs ready"

step "Waiting for financial-services + per-agent ACK resources"
# Every agent with an agentcore.* toggle gets an AgentCoreMemory /
# AgentCoreBrowser / AgentCoreCodeInterpreter composite claim. Its kro RGD
# emits the underlying ACK Memory/Browser/CodeInterpreter and a Secret that
# carries status.id into the <agent>-<kind>-outputs Secret agent pods read.
kubectl -n argocd wait application/financial-services \
  --for=jsonpath='{.status.sync.status}'=Synced --timeout=15m || true
# Wait on the ACK AgentCore resources reaching ACK.ResourceSynced=True — that
# flips once the AWS resource exists and status.id is populated (which in turn
# lets the RGD write the Secret).
for kind in memories browsers codeinterpreters; do
  for r in $(kubectl -n financial-services get ${kind}.bedrockagentcorecontrol.services.k8s.aws -o name 2>/dev/null); do
    echo "  - waiting on ${r}"
    kubectl -n financial-services wait ${r} \
      --for=condition=ACK.ResourceSynced --timeout=10m || true
  done
done
# Per-agent IAM Role + Pod Identity association (ACK, namespaced).
for kind in roles.iam.services.k8s.aws podidentityassociations.eks.services.k8s.aws; do
  for r in $(kubectl -n financial-services get ${kind} -o name 2>/dev/null); do
    echo "  - waiting on ${r}"
    kubectl -n financial-services wait ${r} \
      --for=condition=ACK.ResourceSynced --timeout=10m || true
  done
done
# Confirm the RGD-emitted Secrets carry a non-empty id before the restart.
for kind in memory browser code-interpreter; do
  for sec in $(kubectl -n financial-services get secret -o name 2>/dev/null | grep -- "-${kind}-outputs"); do
    echo "  - checking ${sec} has id"
    for _ in $(seq 1 30); do
      kubectl -n financial-services get "${sec}" -o jsonpath='{.data.id}' 2>/dev/null | grep -q . && break
      sleep 10
    done
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
   • Capabilities      : aws eks list-capabilities --cluster-name ${CLUSTER} --region ${REGION}
   • RGDs              : kubectl get resourcegraphdefinitions
   • AgentCore claims  : kubectl get agentcorememories,agentcorebrowsers,agentcorecodeinterpreters -n financial-services
   • ACK AgentCore     : kubectl get memories,browsers,codeinterpreters.bedrockagentcorecontrol.services.k8s.aws -n financial-services
   • Agent IAM + PIA   : kubectl get roles.iam.services.k8s.aws,podidentityassociations.eks.services.k8s.aws -n financial-services
   • Jaeger UI         : kubectl port-forward -n agentgateway-system svc/jaeger 16686:16686
   • LiteLLM admin     : kubectl port-forward -n litellm svc/litellm 4000:4000

EOF
