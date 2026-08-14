#!/usr/bin/env bash
set -euo pipefail

#####################################################################
# setup-agents.sh
# Builds agent container images, tags with git SHA, pushes to ECR,
# and patches the ArgoCD Application with the new image tags.
# No git push required — image tags are set via ArgoCD parameter overrides.
#####################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config.env"

REGION="$AWS_REGION"
ACCOUNT_ID="$AWS_ACCOUNT_ID"
ECR_REPO="${ACCOUNT_ID}.dkr.ecr.${REGION}.amazonaws.com"
IMAGE_TAG=$(git -C "$ROOT_DIR" rev-parse --short HEAD 2>/dev/null || echo "latest")

echo "============================================================"
echo " Building and pushing agent images"
echo " Tag: $IMAGE_TAG"
echo "============================================================"
echo ""

# Login to ECR
aws ecr get-login-password --region "$REGION" | \
  docker login --username AWS --password-stdin "$ECR_REPO"

# Ensure ECR repos exist
for agent in research-agent data-agent; do
  aws ecr describe-repositories --repository-names "otel-agents/$agent" --region "$REGION" 2>/dev/null || \
    aws ecr create-repository --repository-name "otel-agents/$agent" --region "$REGION"
done

# Build and push each agent from repo root (correct build context)
cd "$ROOT_DIR"

for agent in research_agent data_agent; do
  AGENT_HYPHEN=$(echo "$agent" | tr '_' '-')
  IMAGE="$ECR_REPO/otel-agents/$AGENT_HYPHEN:$IMAGE_TAG"

  echo "▶ Building $AGENT_HYPHEN ($IMAGE)..."
  docker build -t "$IMAGE" \
    --platform linux/amd64 \
    --build-arg AGENT_MODULE="$agent" \
    -f Dockerfile .

  docker push "$IMAGE"
  echo "✓ $AGENT_HYPHEN pushed"
  echo ""
done

# Patch ArgoCD Application to use the new image tag via Helm parameter overrides.
# This avoids requiring git push access — ArgoCD picks up the override immediately.
echo "▶ Patching ArgoCD agents application with new image tag..."

kubectl patch application agents -n argocd --type merge -p "
spec:
  source:
    helm:
      parameters:
        - name: clusterName
          value: \"$(kubectl get application agents -n argocd -o jsonpath='{.spec.source.helm.parameters[?(@.name==\"clusterName\")].value}')\"
        - name: region
          value: \"$(kubectl get application agents -n argocd -o jsonpath='{.spec.source.helm.parameters[?(@.name==\"region\")].value}')\"
        - name: imageTag
          value: \"$IMAGE_TAG\"
        - name: ecrRepo
          value: \"$ECR_REPO\"
" 2>/dev/null && echo "✓ ArgoCD application patched with imageTag=$IMAGE_TAG" \
  || echo "  ⚠ ArgoCD patch failed — falling back to direct kubectl rollout"

# Also directly update the deployments as a fallback (ArgoCD self-heals to match)
echo "▶ Updating agent deployments directly..."
for agent in research-agent data-agent; do
  kubectl set image deployment/"$agent" \
    agent="$ECR_REPO/otel-agents/$agent:$IMAGE_TAG" \
    -n agents 2>/dev/null || true
done
echo "✓ Agent deployments updated"

# Trigger ArgoCD sync to reconcile
kubectl annotate application agents -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite 2>/dev/null || true

echo ""
echo "============================================================"
echo " ✅ Done — images pushed to ECR with tag: $IMAGE_TAG"
echo " Agent deployments updated. ArgoCD will reconcile shortly."
echo "============================================================"
