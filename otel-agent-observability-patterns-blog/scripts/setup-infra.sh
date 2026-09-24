#!/usr/bin/env bash
set -euo pipefail

#####################################################################
# setup-infra.sh
# Provisions infrastructure and bootstraps ArgoCD which then manages
# all workloads (agents, OTEL Collector, Langfuse, Bifrost) via GitOps.
#
# What this script does:
#   1. Terraform: VPC, EKS cluster (Auto Mode), Pod Identity
#   2. Configures kubectl
#   3. Bootstraps ArgoCD
#   4. Generates credentials (no secrets committed to git)
#   5. Syncs the ArgoCD root Application (which deploys everything else)
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
echo "         (EKS Auto Mode, Pod Identity)"
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
# Step 3: Bootstrap ArgoCD
# ---------------------------------------------------------------
echo "▶ [3/5] Bootstrapping ArgoCD..."
echo ""

cd "$ROOT_DIR/terraform/bootstrap"

terraform init -input=false

terraform plan \
  -var="cluster_name=$EKS_CLUSTER_NAME" \
  -var="region=$REGION" \
  -out=tfplan

terraform apply -auto-approve tfplan

echo ""
echo "✓ ArgoCD installed"
echo ""

# ---------------------------------------------------------------
# Step 4: Generate credentials (BEFORE ArgoCD syncs Langfuse)
#
# No secret values are committed to git — the manifests carry only
# PLACEHOLDER values, and ArgoCD's ignoreDifferences on Secret `data`
# keeps self-heal from reverting what we write here. We create the
# namespaces and Secrets now, before the root Application syncs, so
# Langfuse's headless init seeds its project with the real keys on
# first boot (no placeholder race).
#
# The Langfuse project keys are generated once and used consistently in
# three places so ingestion works immediately:
#   1. langfuse-init-keys  → seeds the auto-created Langfuse project
#   2. langfuse-api-keys   → read by agents (Pattern 1) and the collector
#   3. LANGFUSE_AUTH_TOKEN → base64(publicKey:secretKey) for OTLP Basic auth
# ---------------------------------------------------------------
echo "▶ [4/5] Generating credentials (Langfuse, Postgres, ClickHouse, MinIO)..."
echo ""

rand()      { openssl rand -hex 24; }          # generic 48-char hex secret
rand_short(){ openssl rand -hex 8; }           # short suffix

# Langfuse project keys (follow the pk-lf-/sk-lf- convention)
LF_PUBLIC_KEY="pk-lf-$(rand_short)$(rand_short)"
LF_SECRET_KEY="sk-lf-$(rand)"
LF_AUTH_TOKEN=$(printf '%s:%s' "$LF_PUBLIC_KEY" "$LF_SECRET_KEY" | base64 | tr -d '\n')

# Backing-store credentials
PG_PASSWORD=$(rand)
CH_PASSWORD=$(rand)
NEXTAUTH_SECRET=$(rand)
LF_SALT=$(rand)
MINIO_USER="lf-$(rand_short)"
MINIO_PASSWORD=$(rand)
ADMIN_PASSWORD="$(rand_short)$(rand_short)Aa1!"   # satisfies complexity rules

DATABASE_URL="postgresql://langfuse:${PG_PASSWORD}@langfuse-postgres:5432/langfuse"

# Namespaces must exist before we create Secrets in them.
kubectl create ns observability 2>/dev/null || true
kubectl create ns agents 2>/dev/null || true

echo "  Writing Langfuse backing-store secret (langfuse-secrets)..."
kubectl create secret generic langfuse-secrets \
  -n observability \
  --from-literal=DATABASE_URL="$DATABASE_URL" \
  --from-literal=POSTGRES_PASSWORD="$PG_PASSWORD" \
  --from-literal=NEXTAUTH_SECRET="$NEXTAUTH_SECRET" \
  --from-literal=SALT="$LF_SALT" \
  --from-literal=CLICKHOUSE_PASSWORD="$CH_PASSWORD" \
  --from-literal=LANGFUSE_S3_EVENT_UPLOAD_ACCESS_KEY_ID="$MINIO_USER" \
  --from-literal=LANGFUSE_S3_EVENT_UPLOAD_SECRET_ACCESS_KEY="$MINIO_PASSWORD" \
  --from-literal=MINIO_ROOT_USER="$MINIO_USER" \
  --from-literal=MINIO_ROOT_PASSWORD="$MINIO_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "  Writing Langfuse headless-init keys (langfuse-init-keys)..."
kubectl create secret generic langfuse-init-keys \
  -n observability \
  --from-literal=LANGFUSE_INIT_PROJECT_PUBLIC_KEY="$LF_PUBLIC_KEY" \
  --from-literal=LANGFUSE_INIT_PROJECT_SECRET_KEY="$LF_SECRET_KEY" \
  --from-literal=LANGFUSE_INIT_USER_PASSWORD="$ADMIN_PASSWORD" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "  Writing Langfuse API keys (langfuse-api-keys) in both namespaces..."
for NS in observability agents; do
  kubectl create secret generic langfuse-api-keys \
    -n "$NS" \
    --from-literal=LANGFUSE_PUBLIC_KEY="$LF_PUBLIC_KEY" \
    --from-literal=LANGFUSE_SECRET_KEY="$LF_SECRET_KEY" \
    --from-literal=LANGFUSE_AUTH_TOKEN="$LF_AUTH_TOKEN" \
    --dry-run=client -o yaml | kubectl apply -f -
done
echo "✓ Credentials generated (admin password stored in langfuse-init-keys)"
echo ""

# ---------------------------------------------------------------
# Step 5: Deploy root ArgoCD Application
# ---------------------------------------------------------------
echo "▶ [5/5] Deploying ArgoCD root Application (syncs all workloads)..."
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
        # Thread the GitOps source through to the child apps so they sync
        # from the same repo/branch as this root app (from config.env).
        - name: gitops.repoURL
          value: "$GIT_REPO_URL"
        - name: gitops.targetRevision
          value: "$GIT_TARGET_REVISION"
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
echo "  Waiting for Bifrost..."
kubectl wait --for=condition=available deployment/bifrost \
  -n observability --timeout=300s 2>/dev/null || \
kubectl wait --for=jsonpath='{.status.readyReplicas}'=1 statefulset/bifrost \
  -n observability --timeout=300s 2>/dev/null || echo "  (bifrost still syncing)"

# Seed Bifrost with Bedrock provider config and OTEL plugin.
# The Bifrost Helm chart deploys the binary but provider/plugin config
# must be injected via the API at runtime.
echo "  Seeding Bifrost with Bedrock provider and OTEL plugin..."
kubectl delete job/bifrost-seed-provider -n observability 2>/dev/null || true
kubectl apply -f "$ROOT_DIR/gitops/addons/bifrost/seed-provider-job.yaml"
kubectl wait --for=condition=complete job/bifrost-seed-provider \
  -n observability --timeout=300s 2>/dev/null && echo "  ✓ Bifrost seeded" \
  || echo "  ⚠ Bifrost seed job did not complete — check: kubectl logs job/bifrost-seed-provider -n observability"

echo ""
echo "  Waiting for Langfuse..."
kubectl wait --for=condition=available deployment -l app.kubernetes.io/name=langfuse \
  -n observability --timeout=600s 2>/dev/null || echo "  (langfuse still syncing)"

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
echo " ArgoCD:      kubectl port-forward svc/argocd-server -n argocd 8080:443"
echo " Langfuse:    kubectl port-forward svc/langfuse-web -n observability 3000:3000"
echo ""
echo " ArgoCD manages all workloads:"
echo "   • agents (namespace: agents)"
echo "   • bifrost (namespace: observability) — shared LLM gateway"
echo "   • langfuse (namespace: observability)"
echo "   • otel-collector (namespace: observability) — Pattern 2 only"
echo ""
echo " Verify observability:"
echo "   ./scripts/verify-observability.sh"
echo ""
