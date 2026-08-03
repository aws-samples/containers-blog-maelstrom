#!/usr/bin/env bash
set -euo pipefail

#####################################################################
# setup-agents.sh
# Builds agent container images, tags with git SHA, pushes to ECR,
# and updates the ArgoCD agent values with the new image tags.
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
    --build-arg AGENT_MODULE="$agent" \
    -f Dockerfile .

  docker push "$IMAGE"
  echo "✓ $AGENT_HYPHEN pushed"
  echo ""
done

# Update ArgoCD agent values with new image tags
echo "▶ Updating agent image tags in gitops values..."
AGENTS_VALUES="$ROOT_DIR/gitops/addons/agents/values.yaml"

sed -i.bak "/name: research-agent/{n;n;s|image: .*|image: $ECR_REPO/otel-agents/research-agent:$IMAGE_TAG|;}" "$AGENTS_VALUES"
sed -i.bak "/name: data-agent/{n;n;s|image: .*|image: $ECR_REPO/otel-agents/data-agent:$IMAGE_TAG|;}" "$AGENTS_VALUES"
rm -f "${AGENTS_VALUES}.bak"

echo "✓ Values updated. ArgoCD will detect the change and roll out."
echo ""

# Commit and push the updated image tags so ArgoCD can sync
echo "▶ Pushing updated image tags to git..."
GIT_ROOT=$(cd "$ROOT_DIR" && git rev-parse --show-toplevel)
cd "$GIT_ROOT"
git add "$AGENTS_VALUES"
git commit -m "chore: update agent image tags to $IMAGE_TAG" --quiet
git push origin "$(git branch --show-current)" --quiet 2>&1 || echo "  ⚠ git push failed — push manually for ArgoCD to sync"
echo "✓ Pushed to git. ArgoCD will sync within ~3 minutes."
echo ""
echo "============================================================"
echo " ✅ Done — images pushed with tag: $IMAGE_TAG"
echo " ArgoCD will sync within ~3 minutes."
echo "============================================================"
