#!/bin/bash

# format display
log() {
    echo
    if [[ $# -ne 2 ]]; then
        echo -e "\033[0;33m$@\033[0m" # Yellow text
    else
        case $1 in
            G)
                echo -e "\033[0;32m${2}\033[0m" # Green text
                ;;
            O)
                echo -e "\033[0;33m${2}\033[0m" # Orange text
                ;;
            Y)
                echo -e "\033[1;33m${2}\033[0m" # Yellow text
                ;;
            R)
                echo -e "\033[0;31m${2}\033[0m" # Red text
                ;;
            W)
                echo -e "\033[1;37m${2}\033[0m" # White text
                ;;
            C)
                echo -e "\033[0;36m${2}\033[0m" # Cyan text
                ;;
            B)
                echo -e "\033[0;34m${2}\033[0m" # Blue text
                ;;
            P)
                echo -e "\033[0;35m${2}\033[0m" # Purple text
                ;;
            G-H)
                echo -e "\e[37;42m${2}\e[0m" # Green highlighted text
                ;;
            *)
                echo -e "\033[0;33m${2}\033[0m" # Orange text
                ;;
        esac
    fi

}

env_vars_check() {
    # checking environment variables
    if [ -z "${EKSA_CLUSTER_NAME}" ]; then
        log 'R' "env variable EKSA_CLUSTER_NAME not set"; exit 1
    fi

    if [ -z "${EKSA_ADOT_NAMESPACE}" ]; then
        log 'R' "env variable EKSA_ADOT_NAMESPACE not set"; exit 1
    fi

    if [ -z "${EKSA_ADOT_SERVICE_ACCOUNT}" ]; then
        log 'R' "env variable EKSA_ADOT_SERVICE_ACCOUNT not set"; exit 1
    fi

    if [ -z "${EKSA_ES_SERVICE_ACCOUNT}" ]; then
        log 'R' "env variable EKSA_ES_SERVICE_ACCOUNT not set"; exit 1
    fi    
}

# exit when any command fails
set -e

# check for required environment variables
env_vars_check

log 'R' "This step will CLEAN UP all objects, deployments and other resources deployed in Kubernetes cluster as part of the blog post."
read -p "Are you sure you want to proceed [y/N]? " -n 2
if [[ $REPLY =~ ^[Yy]$ ]]
then
    log 'O' "proceeding with clean up steps.."
else
    exit 1
fi

log 'O' "Deleting grafana-kustomization, grafana-repo, configmap created for grafana-operator and GitOps.."
kubectl delete -f https://raw.githubusercontent.com/aws-samples/one-observability-demo/main/gitops/grafana-kustomization.yaml
kubectl delete -f https://raw.githubusercontent.com/aws-samples/one-observability-demo/main/gitops/git-repository.yaml
kubectl delete configmap cluster-vars -n flux-system

log 'O' "Deleting fluxcd.."
kubectl delete -f https://github.com/fluxcd/flux2/releases/latest/download/install.yaml

log 'O' "Uninstalling prometheus-node-exporter using helm.."
helm uninstall prometheus-node-exporter -n prometheus-node-exporter

log 'O' "Uninstalling grafana-operator using helm.."
helm uninstall grafana-operator -n grafana-operator

log 'O' "Uninstalling external-secrets using helm.."
helm uninstall external-secrets -n external-secrets

log 'O' "Deleting $EKSA_ES_SERVICE_ACCOUNT in ${EKSA_ADOT_NAMESPACE}.."
kubectl delete -f ./external-secrets-sa.yaml

log 'O' "Deleting curated package curated-amp-adot.."
eksctl anywhere delete packages curated-amp-adot --cluster $EKSA_CLUSTER_NAME

log 'O' "Deleting $EKSA_ADOT_SERVICE_ACCOUNT in ${EKSA_ADOT_NAMESPACE}.."
kubectl delete -f ./eksa-adot-sa.yaml

log 'O' "Cleaning up manifest files.."
rm -fv ./eksa-externalsecret.yaml ./clustersecretstore.yaml ./external-secrets-sa.yaml ./amp-adot-package.yaml ./eksa-adot-sa.yaml

log 'R' "This step will CLEAN UP NAMESPACES flux-system, prometheus-node-exporter, grafana-operator, external-secrets and ${EKSA_ADOT_NAMESPACE} created in Kubernetes cluster as part of the blog post."
read -p "Are you sure you want to proceed [y/N]? " -n 2
if [[ $REPLY =~ ^[Yy]$ ]]
then
    log 'O' "proceeding with deleting namespaces.."
    kubectl delete ns flux-system prometheus-node-exporter grafana-operator external-secrets ${EKSA_ADOT_NAMESPACE}
fi

log 'G' "CLEAN UP COMPLETE!!!"
