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
# A merge patch replaces the parameters array wholesale, so we must include the
# existing clusterName/region params too. We read those from the live app and
# build the patch with Python to avoid shell quote-escaping issues with jsonpath
# filters (which silently blank the values when run under some shells).
echo "▶ Patching ArgoCD agents application with new image tag..."

APP_JSON=$(kubectl get application platform-root -n argocd -o json)
PATCH=$(printf '%s' "$APP_JSON" | python3 -c "
import sys, json
app = json.load(sys.stdin)
existing = {p['name']: p.get('value', '')
            for p in app['spec']['source']['helm'].get('parameters', [])}
cluster = existing.get('clusterName') or '$EKS_CLUSTER_NAME'
region  = existing.get('region') or '$AWS_REGION'
patch = {'spec': {'source': {'helm': {'parameters': [
    {'name': 'clusterName',     'value': cluster},
    {'name': 'region',          'value': region},
    {'name': 'agents.imageTag', 'value': '$IMAGE_TAG'},
    {'name': 'agents.ecrRepo',  'value': '$ECR_REPO'},
]}}}}
print(json.dumps(patch))
")

kubectl patch application platform-root -n argocd --type merge -p "$PATCH" \
  && echo "✓ ArgoCD application patched with imageTag=$IMAGE_TAG" \
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
kubectl annotate application platform-root -n argocd \
  argocd.argoproj.io/refresh=hard --overwrite 2>/dev/null || true

echo ""
echo "============================================================"
echo " ✅ Done — images pushed to ECR with tag: $IMAGE_TAG"
echo " Agent deployments updated. ArgoCD will reconcile shortly."
echo "============================================================"
