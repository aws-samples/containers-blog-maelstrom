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
    if [ -z "${EKSA_REGION}" ]; then
        log 'R' "env variable EKSA_REGION not set"; exit 1
    fi

    if [ -z "${GO_API_KEY_SECRET_NAME}" ]; then
        log 'R' "env variable GO_API_KEY_SECRET_NAME not set"; exit 1
    fi

    if [ -z "${EKSA_ADOT_SERVICE_ACCOUNT}" ]; then
        log 'R' "env variable EKSA_ADOT_SERVICE_ACCOUNT not set"; exit 1
    fi

    if [ -z "${EKSA_ES_SERVICE_ACCOUNT}" ]; then
        log 'R' "env variable EKSA_ES_SERVICE_ACCOUNT not set"; exit 1
    fi

    if [ -z "${EKSA_AMP_WORKSPACE_ALIAS}" ]; then
        log 'R' "env variable EKSA_AMP_WORKSPACE_ALIAS not set"; exit 1
    fi

    if [ -z "${EKSA_AMG_WORKSPACE_NAME}" ]; then
        log 'R' "env variable EKSA_AMG_WORKSPACE_NAME not set"; exit 1
    fi
}

# exit when any command fails
set -e

# check for required environment variables
env_vars_check

log 'R' "This step will CLEAN UP all AWS resources deployed as part of the blog post."
read -p "Are you sure you want to proceed [y/N]? " -n 2
if [[ $REPLY =~ ^[Yy]$ ]]
then
    log 'O' "proceeding with clean up steps.."
else
    exit 1
fi

log 'O' "Deleting IAM roles ${EKSA_ES_SERVICE_ACCOUNT}-role, ${EKSA_ADOT_SERVICE_ACCOUNT}-role and their policies.."
aws iam delete-role-policy --role-name ${EKSA_ES_SERVICE_ACCOUNT}-role --policy-name secrets-manager-PermissionPolicy
aws iam delete-role --role-name ${EKSA_ES_SERVICE_ACCOUNT}-role

aws iam delete-role-policy --role-name ${EKSA_ADOT_SERVICE_ACCOUNT}-role --policy-name IRSA-AMP-PermissionPolicy
aws iam delete-role --role-name ${EKSA_ADOT_SERVICE_ACCOUNT}-role

log 'O' "Cleaning up IAM policy files.."
rm -fv ./secrets-manager-perm-policy.json ./secrets-manager-trust-policy.json ./amp-irsa-perm-policy.json ./irsa-trust-policy.json

log 'O' "Deleting SecretsManager secret $GO_API_KEY_SECRET_NAME with recovery window of 7 days.."
aws secretsmanager delete-secret --region ${EKSA_REGION} --secret-id $GO_API_KEY_SECRET_NAME --recovery-window-in-days=7

log 'O' "Deleting Grafana workspace API key.."
export GO_AMG_WORKSPACE_ID=$(aws grafana list-workspaces --region ${EKSA_REGION} --query "workspaces[?name=='${EKSA_AMG_WORKSPACE_NAME}'].id" --output text)
aws grafana delete-workspace-api-key --key-name "grafana-operator-key" --workspace-id $GO_AMG_WORKSPACE_ID

log 'O' "Deleting AMP workspace.."
export EKSA_AMP_WORKSPACE_ID=$(aws amp list-workspaces --region=${EKSA_REGION} --alias ${EKSA_AMP_WORKSPACE_ALIAS} --query 'workspaces[0].[workspaceId]' --output text)
aws amp delete-workspace --region ${EKSA_REGION} --workspace-id $EKSA_AMP_WORKSPACE_ID

log 'G' "CLEAN UP COMPLETE!!!"
