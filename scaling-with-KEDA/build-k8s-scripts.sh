#!/usr/bin/env bash

echo "EKS Cluster Name" $CW_KEDA_CLUSTER
echo "AWS Region" $CW_AWS_REGION
echo "HO11Y Image :" $CW_HO11Y_IMAGE

if [ -z "$CW_KEDA_CLUSTER" ]; then
  echo "\CW_KEDA_CLUSTER environement variable is empty."
  exit 1
fi

if [ -z "$CW_AWS_REGION" ]; then
  echo "\CW_AWS_REGION environement variable is empty."
  exit 1
fi

if [ -z "$CW_HO11Y_IMAGE" ]; then
  echo "\CW_HO11Y_IMAGE environement variable is empty."
  exit 1
fi

sed -e "s|{{CW_KEDA_CLUSTER}}|$CW_KEDA_CLUSTER|g" \
  -e "s|{{CW_AWS_REGION}}|$CW_AWS_REGION|g" \
    ./templates/eks-cluster-config.yaml \
  > ./build/eks-cluster-config.yaml

sed -e "s|{{HOLLY_IMAGE}}|$CW_HO11Y_IMAGE|g" \
    ./templates/ho11y-app.yaml \
  > ./build/ho11y-app.yaml

sed -e "s|{{CW_KEDA_CLUSTER}}|$CW_KEDA_CLUSTER|g" \
  -e "s|{{CW_AWS_REGION}}|$CW_AWS_REGION|g" \
    ./templates/cw-eks-adot-prometheus-daemonset.yaml \
  > ./build/cw-eks-adot-prometheus-daemonset.yaml

sed -e "s|{{CW_AWS_REGION}}|$CW_AWS_REGION|g" \
    ./templates/keda-sigv4.yaml \
  > ./build/keda-sigv4.yaml

sed  -e "s|{{CW_AWS_REGION}}|$CW_AWS_REGION|g" \
    ./templates/scaledobject.yaml \
  > ./build/scaledobject.yaml