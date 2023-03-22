#!/bin/bash
set -e
# export PATH=$PATH:/root/bin
HOME=/home/kubectl

export KUBECONFIG=$HOME/.kube/kubeconfig
export AWS_DEFAULT_REGION=$REGION

CLUSTER_NAME=${CLUSTER_NAME-default}

update_kubeconfig(){
    if [[ -n ${EKS_ROLE_ARN} ]]; then
        echo "[INFO] got EKS_ROLE_ARN=${EKS_ROLE_ARN}, updating kubeconfig with this role"
        aws eks update-kubeconfig --name $CLUSTER_NAME --kubeconfig $KUBECONFIG --role-arn "${EKS_ROLE_ARN}"
    else
        aws eks update-kubeconfig --name $CLUSTER_NAME --kubeconfig $KUBECONFIG    
    fi
}

update_kubeconfig
exec "$@"