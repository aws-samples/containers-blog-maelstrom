#!/usr/bin/env bash
#
# 99-cleanup-orphaned-volumes.sh — Delete EBS volumes left behind after
# `eksctl delete cluster`.
#
# Why they leak: the PVCs (DevLake MySQL, Grafana, Gitea, Gitea's Valkey) use
# reclaimPolicy Delete, but the volume is only deleted by the EBS CSI controller
# running in the cluster. Deleting the cluster while PVCs still exist removes
# that controller first, so the volumes are left "available" and keep billing.
# The teardown deletes PVCs before the cluster to avoid this; this script is the
# safety net that sweeps whatever is left.
#
# Run it AFTER the cluster is deleted. It only touches volumes that are:
#   - tagged as belonging to this cluster (eks:eks-cluster-name=<cluster>, set
#     by EKS Auto Mode, or kubernetes.io/cluster/<cluster>), AND
#   - in state "available" (not attached to anything).
# It lists them and asks for confirmation before deleting. Pass --yes to skip
# the prompt.
#
set -euo pipefail

ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
CLUSTER_CONFIG="${ROOT_DIR}/cluster/cluster.yaml"

# Same parsing as 00-create-cluster.sh so the two stay in sync with cluster.yaml.
CLUSTER_NAME="${CLUSTER_NAME:-$(awk '/^metadata:/{m=1} m&&/name:/{print $2; exit}' "${CLUSTER_CONFIG}")}"
CLUSTER_REGION="${CLUSTER_REGION:-$(awk '/^metadata:/{m=1} m&&/region:/{print $2; exit}' "${CLUSTER_CONFIG}")}"

ASSUME_YES=false
[[ "${1:-}" == "--yes" ]] && ASSUME_YES=true

if eksctl get cluster --name "${CLUSTER_NAME}" --region "${CLUSTER_REGION}" >/dev/null 2>&1; then
  echo "Cluster '${CLUSTER_NAME}' still exists in ${CLUSTER_REGION}."
  echo "Run this after 'eksctl delete cluster' has finished."
  exit 1
fi

echo "==> Looking for unattached EBS volumes from cluster '${CLUSTER_NAME}' in ${CLUSTER_REGION}..."

list_volumes() {
  aws ec2 describe-volumes --region "${CLUSTER_REGION}" \
    --filters "Name=status,Values=available" "$@" \
    --query 'Volumes[].VolumeId' --output text
}

# Collect from both tag schemes and de-duplicate.
VOLUME_IDS=$(
  {
    list_volumes "Name=tag:eks:eks-cluster-name,Values=${CLUSTER_NAME}"
    list_volumes "Name=tag-key,Values=kubernetes.io/cluster/${CLUSTER_NAME}"
  } | tr '\t' '\n' | grep -v '^$' | sort -u || true
)

if [[ -z "${VOLUME_IDS}" ]]; then
  echo "    None found. Nothing to clean up."
  exit 0
fi

# Show what will be deleted, including the PVC each volume backed.
# shellcheck disable=SC2086
aws ec2 describe-volumes --region "${CLUSTER_REGION}" --volume-ids ${VOLUME_IDS} \
  --query 'Volumes[].{Id:VolumeId,SizeGiB:Size,Created:CreateTime,PVC:Tags[?Key==`kubernetes.io/created-for/pvc/name`]|[0].Value}' \
  --output table

COUNT=$(wc -l <<<"${VOLUME_IDS}" | tr -d ' ')
if [[ "${ASSUME_YES}" != true ]]; then
  read -r -p "Delete these ${COUNT} volume(s)? This cannot be undone. [y/N] " reply
  [[ "${reply}" =~ ^[Yy]$ ]] || { echo "Aborted."; exit 1; }
fi

for vol in ${VOLUME_IDS}; do
  echo "    Deleting ${vol}..."
  aws ec2 delete-volume --region "${CLUSTER_REGION}" --volume-id "${vol}"
done

echo "==> Deleted ${COUNT} volume(s)."
