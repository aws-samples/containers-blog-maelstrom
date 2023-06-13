kubectl delete -f https://raw.githubusercontent.com/aws-samples/one-observability-demo/main/gitops/grafana-kustomization.yaml
kubectl delete -f https://raw.githubusercontent.com/aws-samples/one-observability-demo/main/gitops/git-repository.yaml
kubectl delete configmap cluster-vars -n flux-system

#removing fluxcd
kubectl apply -f https://github.com/fluxcd/flux2/releases/latest/download/install.yaml

helm uninstall prometheus-node-exporter -n prometheus-node-exporter
helm uninstall grafana-operator -n grafana-operator
helm uninstall external-secrets -n external-secrets
kubectl delete -f ./external-secrets-sa.yaml

eksctl anywhere delete packages curated-amp-adot --cluster $EKSA_CLUSTER_NAME
kubectl delete -f ./eksa-adot-sa.yaml

kubectl delete ns flux-system prometheus-node-exporter grafana-operator external-secrets observability
rm -f ./eksa-externalsecret.yaml ./clustersecretstore.yaml ./external-secrets-sa.yaml ./amp-adot-package.yaml ./eksa-adot-sa.yaml
---

aws iam delete-role-policy --role-name ${EKSA_ES_SERVICE_ACCOUNT}-role --policy-name secrets-manager-PermissionPolicy
aws iam delete-role --role-name ${EKSA_ES_SERVICE_ACCOUNT}-role

aws secretsmanager delete-secret --region ${EKSA_REGION} --secret-id $GO_API_KEY_SECRET_NAME --recovery-window-in-days=7

aws grafana delete-workspace-api-key --key-name "grafana-operator-key" --workspace-id $GO_AMG_WORKSPACE_ID

aws iam delete-role-policy --role-name ${EKSA_ADOT_SERVICE_ACCOUNT}-role --policy-name IRSA-AMP-PermissionPolicy
aws iam delete-role --role-name ${EKSA_ADOT_SERVICE_ACCOUNT}-role

export EKSA_AMP_WORKSPACE_ID=$(aws amp list-workspaces \
    --region=${EKSA_REGION} \
    --alias ${EKSA_AMP_WORKSPACE_ALIAS} \
    --query 'workspaces[0].[workspaceId]' \
    --output text)
aws amp delete-workspace --region ${EKSA_REGION} --workspace-id $EKSA_AMP_WORKSPACE_ID

rm -f ./secrets-manager-perm-policy.json ./secrets-manager-trust-policy.json ./amp-irsa-perm-policy.json ./irsa-trust-policy.json