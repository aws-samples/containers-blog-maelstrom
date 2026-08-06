#!/usr/bin/env bash
set -euo pipefail

#####################################################################
# setup-infra.sh
# Provisions infrastructure and bootstraps ArgoCD which then manages
# all workloads (agents, OTEL Collector, Langfuse, Bifrost) via GitOps.
#
# What this script does:
#   1. Terraform: VPC, EKS cluster (Auto Mode), Pod Identity, ACK + kro
#   2. Configures kubectl
#   3. Bootstraps ArgoCD + kro RBAC
#   4. Syncs the ArgoCD root Application (which deploys everything else)
#
# EKS Auto Mode handles compute — no node groups or managed node pools.
# Pods run on Auto Mode managed instances that scale automatically.
#
# Prerequisites:
#   - AWS CLI v2 configured with credentials
#   - Terraform >= 1.5
#   - kubectl, helm 3.x
#####################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config.env"

CLUSTER_NAME="$EKS_CLUSTER_NAME"
REGION="$AWS_REGION"

echo "============================================================"
echo " OTEL Agent Observability — Infrastructure Setup"
echo "============================================================"
echo " Cluster:  $CLUSTER_NAME"
echo " Region:   $REGION"
echo "============================================================"
echo ""

# ---------------------------------------------------------------
# Step 1: Provision EKS cluster + networking + IAM
# ---------------------------------------------------------------
echo "▶ [1/5] Provisioning EKS cluster and AWS resources..."
echo "         (EKS Auto Mode, Pod Identity, ACK + kro)"
echo ""

cd "$ROOT_DIR/terraform/cluster"

terraform init -input=false

terraform plan \
  -var="cluster_name=$CLUSTER_NAME" \
  -var="region=$REGION" \
  -out=tfplan

terraform apply -auto-approve tfplan

export EKS_CLUSTER_NAME=$(terraform output -raw cluster_name)
EKS_VERSION=$(terraform output -raw eks_version)

echo ""
echo "✓ EKS cluster provisioned: $EKS_CLUSTER_NAME (v$EKS_VERSION, Auto Mode)"
echo "✓ ACK + kro EKS Capabilities created"
echo ""

# ---------------------------------------------------------------
# Step 2: Configure kubectl
# ---------------------------------------------------------------
echo "▶ [2/5] Configuring kubectl context..."
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
echo "▶ [3/5] Bootstrapping ArgoCD and kro RBAC..."
echo ""

cd "$ROOT_DIR/terraform/bootstrap"

terraform init -input=false

KRO_ROLE_ARN=$(cd "$ROOT_DIR/terraform/cluster" && terraform output -raw kro_role_arn)

terraform plan \
  -var="cluster_name=$EKS_CLUSTER_NAME" \
  -var="region=$REGION" \
  -var="kro_role_arn=$KRO_ROLE_ARN" \
  -out=tfplan

terraform apply -auto-approve tfplan

echo ""
echo "✓ ArgoCD installed"
echo "✓ kro RBAC granted over *.services.k8s.aws CRDs"
echo ""

# ---------------------------------------------------------------
# Step 4: Deploy root ArgoCD Application
# ---------------------------------------------------------------
echo "▶ [4/5] Deploying ArgoCD root Application (syncs all workloads)..."
echo ""

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

echo ""
echo "  Waiting for Langfuse..."
kubectl wait --for=condition=available deployment -l app.kubernetes.io/name=langfuse \
  -n observability --timeout=300s 2>/dev/null || echo "  (langfuse still syncing)"

echo "  Waiting for Bifrost..."
kubectl wait --for=condition=available deployment/bifrost \
  -n agents --timeout=300s 2>/dev/null || echo "  (bifrost still syncing)"

echo "  Waiting for agent pods..."
kubectl wait --for=condition=available deployment -l app.kubernetes.io/component=agent \
  -n agents --timeout=300s 2>/dev/null || echo "  (agents still syncing)"

echo ""
echo "✓ ArgoCD root application synced"
echo ""

# ---------------------------------------------------------------
# Step 5: Configure Langfuse API keys automatically
# ---------------------------------------------------------------
echo "▶ [5/5] Configuring Langfuse API keys..."
echo ""

"$SCRIPT_DIR/setup-langfuse-keys.sh"

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
echo " ArgoCD:      kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo " Langfuse:    kubectl port-forward svc/langfuse-web -n observability 3000:3000"
echo ""
echo " ArgoCD manages all workloads:"
echo "   • agents (namespace: agents)"
echo "   • bifrost (namespace: agents)"
echo "   • langfuse (namespace: observability)"
echo "   • otel-collector (namespace: observability) — Pattern 2 only"
echo "   • agentcore-rgds (kro ResourceGraphDefinitions)"
echo ""
echo " Verify observability:"
echo "   ./scripts/verify-observability.sh"
echo ""
