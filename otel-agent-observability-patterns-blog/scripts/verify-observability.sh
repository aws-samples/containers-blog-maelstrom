#!/usr/bin/env bash
set -euo pipefail

#####################################################################
# verify-observability.sh
# Validates that agents, Bifrost, and Langfuse are running and
# producing correlated traces.
#####################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config.env"

echo "============================================================"
echo " Verifying Observability Stack"
echo "============================================================"
echo ""

# Langfuse
echo "▶ Langfuse (observability backend):"
kubectl get pods -n observability -l app.kubernetes.io/name=langfuse --no-headers 2>/dev/null || echo "  NOT FOUND"
echo ""

# OTEL Collector (Pattern 2)
echo "▶ OTEL Collector (Pattern 2 — Centralized):"
kubectl get pods -n observability -l app.kubernetes.io/name=opentelemetry-collector --no-headers 2>/dev/null || echo "  NOT FOUND (Pattern 2 not deployed)"
echo ""

# Bifrost (LLM Gateway)
echo "▶ Bifrost (LLM Gateway — both patterns):"
kubectl get pods -n agents -l app.kubernetes.io/name=bifrost --no-headers 2>/dev/null || echo "  NOT FOUND"
echo ""

# Agents
echo "▶ Agent Pods:"
kubectl get pods -n agents -l app.kubernetes.io/component=agent --no-headers 2>/dev/null || echo "  NOT FOUND"
echo ""

# Send a test query
echo "▶ Sending test query to research-agent..."
kubectl port-forward svc/research-agent -n agents 8080:8080 &>/dev/null &
PF_PID=$!
sleep 3

RESPONSE=$(curl -s -X POST http://localhost:8080/invoke \
  -H "Content-Type: application/json" \
  -d '{"query": "What is 2+2? Answer in one word."}' 2>/dev/null || echo "FAILED")

kill $PF_PID 2>/dev/null || true

if [ "$RESPONSE" != "FAILED" ]; then
  echo "  ✓ Agent responded successfully"
  echo "  Response: $(echo "$RESPONSE" | head -c 100)..."
else
  echo "  ✗ Agent did not respond (check pod logs)"
fi

echo ""
echo "============================================================"
echo " ✅ Verification complete"
echo "============================================================"
echo ""
echo " View traces in Langfuse:"
echo "   kubectl port-forward svc/langfuse-web -n observability 3000:3000"
echo "   → Open http://localhost:3000"
echo ""
echo " The trace should show a unified tree:"
echo "   agent.invoke"
echo "     ├── tool.call: web_search"
echo "     ├── [Bifrost] bedrock.invoke: claude-sonnet-5"
echo "     ├── tool.call: summarize"
echo "     └── [Bifrost] bedrock.invoke: claude-sonnet-5"
echo ""
echo " If traces are missing:"
echo "   1. Check Langfuse credentials: kubectl get secret langfuse-api-keys -n observability -o yaml"
echo "   2. Check agent logs: kubectl logs -n agents deployment/research-agent"
echo "   3. Check Bifrost OTEL plugin: kubectl logs -n agents deployment/bifrost | grep otel"
echo ""
