#!/usr/bin/env bash
#
# 00-create-cluster.sh — Provision the EKS cluster used for the showcase.
#
# Prerequisites: eksctl, kubectl, and valid AWS credentials with permission to
# create EKS clusters, VPCs, and IAM roles. See README.md for install links.
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_CONFIG="${ROOT_DIR}/cluster/cluster.yaml"

# Pull the cluster name/region straight from the config so this stays in sync
# with cluster.yaml (grab the first name: under metadata).
CLUSTER_NAME="$(awk '/^metadata:/{m=1} m&&/name:/{print $2; exit}' "${CLUSTER_CONFIG}")"
CLUSTER_REGION="$(awk '/^metadata:/{m=1} m&&/region:/{print $2; exit}' "${CLUSTER_CONFIG}")"

# Idempotent: skip creation if the cluster already exists, so this script (and
# the install-platform.sh wrapper) can be safely re-run after a mid-way failure.
if eksctl get cluster --name "${CLUSTER_NAME}" --region "${CLUSTER_REGION}" >/dev/null 2>&1; then
  echo "==> Cluster '${CLUSTER_NAME}' already exists in ${CLUSTER_REGION} — skipping creation."
else
  echo "==> Creating EKS cluster (this takes ~15-20 minutes)..."
  eksctl create cluster -f "${CLUSTER_CONFIG}"
fi

echo "==> Verifying the default StorageClass is set (needed for MySQL/Grafana PVCs)..."
# EKS Auto Mode manages block storage but ships NO StorageClass by default, so
# we create a gp3 default backed by the Auto Mode EBS provisioner. Note the
# provisioner is ebs.csi.eks.amazonaws.com (Auto Mode), not the self-managed
# ebs.csi.aws.com driver.
if ! kubectl get storageclass -o jsonpath='{.items[?(@.metadata.annotations.storageclass\.kubernetes\.io/is-default-class=="true")].metadata.name}' | grep -q .; then
  echo "    No default StorageClass found — creating a gp3 default..."
  kubectl apply -f - <<'EOF'
apiVersion: storage.k8s.io/v1
kind: StorageClass
metadata:
  name: gp3
  annotations:
    storageclass.kubernetes.io/is-default-class: "true"
provisioner: ebs.csi.eks.amazonaws.com
volumeBindingMode: WaitForFirstConsumer
parameters:
  type: gp3
EOF
fi

echo "==> Cluster nodes:"
kubectl get nodes -o wide

echo ""
echo "Cluster is ready. Next: ./scripts/10-install-argocd.sh"
