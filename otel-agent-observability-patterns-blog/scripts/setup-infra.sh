#!/usr/bin/env bash
set -euo pipefail

#####################################################################
# setup-infra.sh
# Provisions infrastructure and bootstraps ArgoCD which then manages
# all workloads (agents, OTEL Collector, Langfuse, Bifrost) via GitOps.
#
# What this script does:
#   1. Terraform: VPC, EKS cluster (Auto Mode), Pod Identity,
#      ACK + kro EKS Capabilities, ADOT add-on, AMP, Managed Grafana
#   2. Configures kubectl
#   3. Bootstraps ArgoCD + kro RBAC
#   4. Syncs the ArgoCD root Application (which deploys everything else)
#
# EKS Auto Mode handles compute — no node groups or managed node pools.
# Pods (agents, OTEL Collector, Langfuse, Bifrost) run on Auto Mode
# managed instances that scale automatically based on demand.
#
# Prerequisites:
#   - AWS CLI v2 configured with credentials
#   - Terraform >= 1.5
#   - kubectl
#   - helm 3.x
#
# Usage:
#   ./scripts/setup-infra.sh [CLUSTER_NAME] [REGION]
#####################################################################

# Source central config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config.env"

CLUSTER_NAME="$EKS_CLUSTER_NAME"
REGION="$AWS_REGION"

echo "============================================================"
echo " OTEL Agent Observability - Infrastructure Setup"
echo "============================================================"
echo " Cluster:  $CLUSTER_NAME"
echo " Region:   $REGION"
echo "============================================================"
echo ""

# ---------------------------------------------------------------
# Step 1: Provision EKS cluster + networking + capabilities
# ---------------------------------------------------------------
echo "▶ [1/4] Provisioning EKS cluster and AWS resources..."
echo "         (EKS Auto Mode, Pod Identity, ADOT, ACK, kro, AMP, Grafana)"
echo ""

cd "$ROOT_DIR/terraform/cluster"

terraform init -input=false

terraform plan \
  -var="cluster_name=$CLUSTER_NAME" \
  -var="region=$REGION" \
  -out=tfplan

terraform apply -auto-approve tfplan

# Export outputs
export EKS_CLUSTER_NAME=$(terraform output -raw cluster_name)
export AMP_ENDPOINT=$(terraform output -raw amp_workspace_endpoint)
export AMP_REMOTE_WRITE_ENDPOINT=$(terraform output -raw amp_remote_write_endpoint)
export GRAFANA_ENDPOINT=$(terraform output -raw grafana_workspace_endpoint)

echo ""
EKS_VERSION=$(cd "$ROOT_DIR/terraform/cluster" && terraform output -raw eks_version 2>/dev/null || echo "1.35")
echo "✓ EKS cluster provisioned: $EKS_CLUSTER_NAME (v$EKS_VERSION, Auto Mode)"
echo "✓ ADOT managed add-on installed"
echo "✓ ACK + kro EKS Capabilities created"
echo "✓ AMP workspace: $AMP_ENDPOINT"
echo "✓ Grafana: https://$GRAFANA_ENDPOINT"
echo ""

# ---------------------------------------------------------------
# Step 2: Configure kubectl
# ---------------------------------------------------------------
echo "▶ [2/4] Configuring kubectl context..."
echo ""

aws eks update-kubeconfig \
  --name "$EKS_CLUSTER_NAME" \
  --region "$REGION" \
  --alias "$EKS_CLUSTER_NAME"

echo "✓ kubectl configured for cluster: $EKS_CLUSTER_NAME"
echo ""

# ---------------------------------------------------------------
# Step 3: Bootstrap ArgoCD + kro RBAC
# ---------------------------------------------------------------
echo "▶ [3/4] Bootstrapping ArgoCD and kro RBAC..."
echo ""

cd "$ROOT_DIR/terraform/bootstrap"

terraform init -input=false

KRO_ROLE_ARN=$(cd "$ROOT_DIR/terraform/cluster" && terraform output -raw kro_role_arn)
ADOT_ROLE_ARN=$(cd "$ROOT_DIR/terraform/cluster" && terraform output -raw adot_role_arn)

terraform plan \
  -var="cluster_name=$EKS_CLUSTER_NAME" \
  -var="region=$REGION" \
  -var="amp_remote_write_endpoint=$AMP_REMOTE_WRITE_ENDPOINT" \
  -var="kro_role_arn=$KRO_ROLE_ARN" \
  -var="adot_role_arn=$ADOT_ROLE_ARN" \
  -out=tfplan

terraform apply -auto-approve tfplan

echo ""
echo "✓ ArgoCD installed"
echo "✓ kro RBAC granted over *.services.k8s.aws CRDs"
echo ""

# ---------------------------------------------------------------
# Step 4: Deploy root ArgoCD Application
# ---------------------------------------------------------------
echo "▶ [4/4] Deploying ArgoCD root Application (syncs all workloads)..."
echo ""

# Create the root Application that manages everything via GitOps
kubectl apply -f - <<EOF
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: platform-root
  namespace: argocd
spec:
  project: default
  source:
    repoURL: $GIT_REPO_URL
    targetRevision: $GIT_TARGET_REVISION
    path: otel-agent-observability-patterns-blog/gitops/root
    helm:
      parameters:
        - name: clusterName
          value: "$EKS_CLUSTER_NAME"
        - name: region
          value: "$REGION"
        - name: amp.remoteWriteEndpoint
          value: "$AMP_REMOTE_WRITE_ENDPOINT"
  destination:
    server: https://kubernetes.default.svc
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

echo "  Waiting for ArgoCD to sync all applications..."
sleep 10

# Wait for key deployments to be ready
echo ""
echo "  Waiting for observability stack..."
kubectl wait --for=condition=available deployment/otel-collector \
  -n observability --timeout=300s 2>/dev/null || echo "  (otel-collector still syncing)"
kubectl wait --for=condition=available deployment/langfuse \
  -n observability --timeout=300s 2>/dev/null || echo "  (langfuse still syncing)"

echo "  Waiting for agent pods..."
kubectl wait --for=condition=available deployment -l app.kubernetes.io/component=agent \
  -n agents --timeout=300s 2>/dev/null || echo "  (agents still syncing)"

echo ""
echo "✓ ArgoCD root application synced"
echo ""

# ---------------------------------------------------------------
# Summary
# ---------------------------------------------------------------
echo "============================================================"
echo " ✅ Setup complete!"
echo "============================================================"
echo ""
echo " Cluster:     $EKS_CLUSTER_NAME (EKS v$EKS_VERSION, Auto Mode)"
echo " Region:      $REGION"
echo " AMP:         $AMP_ENDPOINT"
echo " Grafana:     https://$GRAFANA_ENDPOINT"
echo " ArgoCD:      kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo ""
echo " ArgoCD manages all workloads:"
echo "   • agents (namespace: agents)"
echo "   • otel-collector (namespace: observability)"
echo "   • langfuse (namespace: observability)"
echo "   • bifrost (namespace: agents)"
echo "   • agentcore-rgds (kro ResourceGraphDefinitions)"
echo ""
echo " Verify observability:"
echo "   ./scripts/verify-observability.sh"
echo ""
