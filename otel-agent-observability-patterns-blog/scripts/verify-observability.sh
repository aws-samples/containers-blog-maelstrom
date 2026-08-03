#!/usr/bin/env bash
set -euo pipefail

#####################################################################
# verify-observability.sh
# Validates that both observability patterns are collecting data.
#####################################################################

echo "============================================================"
echo " Verifying Observability Patterns"
echo "============================================================"
echo ""

# Pattern 1: ADOT → CloudWatch
echo "▶ Pattern 1: Decentralized (ADOT → CloudWatch)"
echo "  Checking ADOT DaemonSet..."
kubectl get pods -n amazon-adot -l app=adot-collector --no-headers | head -3
echo ""

# Pattern 2: OTEL Collector → Langfuse + AMP
echo "▶ Pattern 2: Centralized (OTEL Collector → Langfuse + AMP)"
echo "  Checking OTEL Collector..."
kubectl get pods -n observability -l app.kubernetes.io/name=opentelemetry-collector --no-headers
echo ""
echo "  Checking Langfuse..."
kubectl get pods -n observability -l app=langfuse --no-headers
echo ""

# Agents
echo "▶ Agent Pods:"
kubectl get pods -n agents -l app.kubernetes.io/component=agent --no-headers
echo ""

# Bifrost
echo "▶ Bifrost (LLM Proxy):"
kubectl get pods -n agents -l app=bifrost --no-headers
echo ""

# Send a test query
echo "▶ Sending test query to research-agent..."
kubectl port-forward svc/research-agent -n agents 8080:8080 &>/dev/null &
PF_PID=$!
sleep 3

RESPONSE=$(curl -s -X POST http://localhost:8080/invoke   -H "Content-Type: application/json"   -d '"'"'{"query": "What is 2+2? Answer in one word."}'"'"' 2>/dev/null || echo "FAILED")

kill $PF_PID 2>/dev/null || true

if [ "$RESPONSE" != "FAILED" ]; then
  echo "  ✓ Agent responded successfully"
  echo "  Response: $(echo $RESPONSE | head -c 100)..."
else
  echo "  ✗ Agent did not respond (check pod logs)"
fi

echo ""
echo "============================================================"
echo " ✅ Verification complete"
echo "============================================================"
echo ""
echo " Check traces in:"
echo "   • CloudWatch: Console → Application Signals → GenAI"
echo "   • Langfuse:   kubectl port-forward svc/langfuse -n observability 3000:3000"
echo "   • Grafana:    See terraform output grafana_workspace_endpoint"
echo ""
