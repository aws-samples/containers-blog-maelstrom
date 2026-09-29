#!/usr/bin/env bash
set -euo pipefail

#####################################################################
# teardown.sh
# Destroys all infrastructure created by setup-infra.sh.
# Deletes workloads, then destroys the bootstrap and cluster
# Terraform state.
#####################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config.env"

CLUSTER_NAME="$EKS_CLUSTER_NAME"
REGION="$AWS_REGION"

echo "============================================================"
echo " OTEL Agent Observability — Teardown"
echo "============================================================"
echo " Cluster: $CLUSTER_NAME | Region: $REGION"
echo "============================================================"
echo ""

# Delete workloads first so ArgoCD-managed resources drain cleanly
echo "▶ Deleting workloads..."
kubectl delete namespace agents --ignore-not-found --timeout=60s 2>/dev/null || true
kubectl delete namespace observability --ignore-not-found --timeout=60s 2>/dev/null || true
echo "  Workloads deleted ✓"
echo ""

# Destroy bootstrap (ArgoCD)
echo "▶ Destroying bootstrap layer..."
cd "$ROOT_DIR/terraform/bootstrap"
terraform destroy -auto-approve \
  -var="cluster_name=$CLUSTER_NAME" \
  -var="region=$REGION" 2>/dev/null || true
echo "  Bootstrap destroyed ✓"
echo ""

# Destroy cluster
echo "▶ Destroying EKS cluster and networking..."
cd "$ROOT_DIR/terraform/cluster"
terraform destroy -auto-approve \
  -var="cluster_name=$CLUSTER_NAME" \
  -var="region=$REGION"
echo "  Cluster destroyed ✓"
echo ""

echo "============================================================"
echo " ✅ Teardown complete. No orphaned AWS resources."
echo "============================================================"
