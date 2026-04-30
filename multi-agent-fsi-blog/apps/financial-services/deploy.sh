#!/usr/bin/env bash
#
# Build and push the 5 container images for the Strands financial-services stack.
# Uses finch (https://runfinch.com) to produce multi-arch (linux/amd64 + linux/arm64)
# images and publishes them to a Docker Hub repository.
#
# Default destination: docker.io/sriram430/financial-services-agents
# Images are distinguished by tag prefix since Docker Hub doesn't support
# nested repository paths the way ECR does:
#
#   docker.io/sriram430/financial-services-agents:financial-tools-mcp-<TAG>
#   docker.io/sriram430/financial-services-agents:financial-advisor-<TAG>
#   docker.io/sriram430/financial-services-agents:portfolio-analyst-<TAG>
#   docker.io/sriram430/financial-services-agents:risk-assessment-<TAG>
#   docker.io/sriram430/financial-services-agents:market-data-<TAG>
#
# Usage:
#   ./deploy.sh                  # build + push all images, platforms amd64+arm64
#   TAG=v2 ./deploy.sh
#   PLATFORMS=linux/amd64 ./deploy.sh   # single-arch (faster)
#   SKIP_LOGIN=1 ./deploy.sh     # skip `finch login` if already authenticated
#
set -euo pipefail

cd "$(dirname "$0")"

REGISTRY="${REGISTRY:-docker.io/sriram430/financial-services-agents}"
TAG="${TAG:-v1}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"
SKIP_LOGIN="${SKIP_LOGIN:-0}"

declare -a REPOS=(
  "financial-tools-mcp:mcp-server"
  "financial-advisor:agents/financial-advisor"
  "portfolio-analyst:agents/portfolio-analyst"
  "risk-assessment:agents/risk-assessment"
  "market-data:agents/market-data"
)

if [[ "${SKIP_LOGIN}" != "1" ]]; then
  echo "--- finch login docker.io (enter Docker Hub username + PAT when prompted)"
  finch login docker.io
fi

for entry in "${REPOS[@]}"; do
  component="${entry%%:*}"
  context="${entry##*:}"
  image="${REGISTRY}:${component}-${TAG}"

  # Agent images share the _shared client library. Their Dockerfiles do
  # `COPY _shared /app/_shared`, so the build context is the parent `agents/`
  # directory and -f points at the sub-dir Dockerfile.
  if [[ "${context}" == agents/* ]]; then
    echo "--- Building ${image} (context=agents, file=${context}/Dockerfile, platforms=${PLATFORMS})"
    finch build \
      --platform "${PLATFORMS}" \
      --tag "${image}" \
      -f "${context}/Dockerfile" \
      agents
  else
    echo "--- Building ${image} (context=${context}, platforms=${PLATFORMS})"
    finch build \
      --platform "${PLATFORMS}" \
      --tag "${image}" \
      "${context}"
  fi

  echo "--- Pushing ${image} (platforms=${PLATFORMS})"
  finch push \
    --platform "${PLATFORMS}" \
    "${image}"
done

echo
echo "All images pushed to ${REGISTRY}."
echo
echo "Helm chart (gitops/financial-services-stack/values.yaml) must reference:"
echo "  images.registry:         ${REGISTRY%/*}"
echo "  images.repository:       ${REGISTRY##*/}"
echo "  images.<component>.tag:  <component>-${TAG}"
echo
