#!/usr/bin/env bash
set -euo pipefail

#####################################################################
# setup-langfuse-keys.sh
# Waits for Langfuse to boot, creates an admin user + project,
# generates API keys, and writes them to the K8s secret.
#
# This eliminates the manual step of opening the UI and generating
# credentials after first deploy.
#
# Idempotent: if langfuse-api-keys secret already has real keys
# (not placeholders), this script exits early.
#####################################################################

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
ROOT_DIR="$(dirname "$SCRIPT_DIR")"
source "$ROOT_DIR/config.env"

NAMESPACE="observability"
SECRET_NAME="langfuse-api-keys"
LANGFUSE_SVC="langfuse-web"
LANGFUSE_PORT="3000"
LOCAL_PORT="3099"  # Use a non-standard port to avoid conflicts

# Admin credentials for the auto-created user
ADMIN_EMAIL="${LANGFUSE_ADMIN_EMAIL:-admin@agent-observability.local}"
ADMIN_PASSWORD="${LANGFUSE_ADMIN_PASSWORD:-AgentObs2026!}"
ADMIN_NAME="${LANGFUSE_ADMIN_NAME:-Admin}"
PROJECT_NAME="agent-observability"

echo "▶ Setting up Langfuse API keys..."

# ---------------------------------------------------------------
# Check if real keys already exist (skip if so)
# ---------------------------------------------------------------
EXISTING_PK=$(kubectl get secret "$SECRET_NAME" -n "$NAMESPACE" \
  -o jsonpath='{.data.LANGFUSE_PUBLIC_KEY}' 2>/dev/null | base64 -d 2>/dev/null || echo "")

if [ -n "$EXISTING_PK" ] && [ "$EXISTING_PK" != "pk-lf-REPLACE-ME" ]; then
  echo "  ✓ Real Langfuse keys already configured (public key: ${EXISTING_PK:0:20}...)"
  echo "  Skipping key generation."
  exit 0
fi

# ---------------------------------------------------------------
# Wait for Langfuse pods to be ready (they need PVCs, DB init, etc.)
# ---------------------------------------------------------------
echo "  Waiting for Langfuse pods to be ready (this may take 5-10 minutes)..."
echo "  (Langfuse needs Postgres, ClickHouse, and Redis to initialize)"

# First wait for the namespace and deployment to exist
DEPLOY_RETRIES=0
until kubectl get deployment -n "$NAMESPACE" -l app.kubernetes.io/name=langfuse -o name 2>/dev/null | grep -q deployment; do
  DEPLOY_RETRIES=$((DEPLOY_RETRIES + 1))
  if [ $DEPLOY_RETRIES -ge 60 ]; then
    echo "  ✗ Langfuse deployment not found after 5 minutes."
    echo "    Check ArgoCD: kubectl get applications -n argocd"
    exit 1
  fi
  sleep 5
done

# Wait for the web deployment to be available (includes DB readiness)
kubectl wait --for=condition=available deployment -l app.kubernetes.io/name=langfuse \
  -n "$NAMESPACE" --timeout=600s 2>&1 || {
  echo "  ✗ Langfuse did not become ready within 10 minutes."
  echo "    Check: kubectl get pods -n $NAMESPACE"
  echo "    Logs:  kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=langfuse --tail=50"
  exit 1
}
echo "  ✓ Langfuse pods are ready"

# Short pause to let the HTTP server finish internal startup
sleep 10

# ---------------------------------------------------------------
# Port-forward Langfuse
# ---------------------------------------------------------------
echo "  Starting port-forward to Langfuse..."
kubectl port-forward "svc/$LANGFUSE_SVC" -n "$NAMESPACE" "$LOCAL_PORT:$LANGFUSE_PORT" &>/dev/null &
PF_PID=$!
trap "kill $PF_PID 2>/dev/null || true" EXIT

LANGFUSE_URL="http://localhost:$LOCAL_PORT"

# ---------------------------------------------------------------
# Wait for Langfuse HTTP endpoint to respond
# ---------------------------------------------------------------
echo "  Waiting for Langfuse health endpoint..."
RETRIES=0
MAX_RETRIES=30
until curl -sf "$LANGFUSE_URL/api/public/health" >/dev/null 2>&1; do
  RETRIES=$((RETRIES + 1))
  if [ $RETRIES -ge $MAX_RETRIES ]; then
    echo "  ✗ Langfuse health endpoint not responding after ${MAX_RETRIES} attempts."
    echo "    Check: kubectl get pods -n $NAMESPACE -l app.kubernetes.io/name=langfuse"
    exit 1
  fi
  sleep 5
done
echo "  ✓ Langfuse is healthy"

# ---------------------------------------------------------------
# Create admin user (only works on fresh install — no users exist)
# ---------------------------------------------------------------
echo "  Creating admin user..."
SIGNUP_RESPONSE=$(curl -sf -X POST "$LANGFUSE_URL/api/auth/signup" \
  -H "Content-Type: application/json" \
  -d "{
    \"name\": \"$ADMIN_NAME\",
    \"email\": \"$ADMIN_EMAIL\",
    \"password\": \"$ADMIN_PASSWORD\"
  }" 2>/dev/null || echo "EXISTING")

if [ "$SIGNUP_RESPONSE" = "EXISTING" ]; then
  echo "  ✓ Admin user already exists (sign-up endpoint returned error — expected)"
else
  echo "  ✓ Admin user created: $ADMIN_EMAIL"
fi

# ---------------------------------------------------------------
# Get auth session token
# ---------------------------------------------------------------
echo "  Authenticating..."

# Langfuse uses NextAuth — get CSRF token first
CSRF_RESPONSE=$(curl -sf -c /tmp/langfuse-cookies "$LANGFUSE_URL/api/auth/csrf" 2>/dev/null)
CSRF_TOKEN=$(echo "$CSRF_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('csrfToken',''))" 2>/dev/null || echo "")

# Sign in with credentials
SIGNIN_RESPONSE=$(curl -sf -b /tmp/langfuse-cookies -c /tmp/langfuse-cookies \
  -X POST "$LANGFUSE_URL/api/auth/callback/credentials" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "email=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$ADMIN_EMAIL'))")&password=$(python3 -c "import urllib.parse; print(urllib.parse.quote('$ADMIN_PASSWORD'))")&csrfToken=$CSRF_TOKEN" \
  -L 2>/dev/null || echo "FAILED")

# Get session to confirm auth works
SESSION=$(curl -sf -b /tmp/langfuse-cookies "$LANGFUSE_URL/api/auth/session" 2>/dev/null || echo "{}")
SESSION_USER=$(echo "$SESSION" | python3 -c "import sys,json; print(json.load(sys.stdin).get('user',{}).get('email',''))" 2>/dev/null || echo "")

if [ -z "$SESSION_USER" ]; then
  echo "  ✗ Authentication failed. Try manually:"
  echo "    kubectl port-forward svc/$LANGFUSE_SVC -n $NAMESPACE 3000:3000"
  echo "    Open http://localhost:3000 and generate keys manually."
  exit 1
fi
echo "  ✓ Authenticated as: $SESSION_USER"

# ---------------------------------------------------------------
# Create project (or find existing)
# ---------------------------------------------------------------
echo "  Creating project '$PROJECT_NAME'..."
PROJECTS=$(curl -sf -b /tmp/langfuse-cookies "$LANGFUSE_URL/api/projects" 2>/dev/null || echo "[]")
PROJECT_ID=$(echo "$PROJECTS" | python3 -c "
import sys, json
data = json.load(sys.stdin)
projects = data if isinstance(data, list) else data.get('data', [])
for p in projects:
    if p.get('name') == '$PROJECT_NAME':
        print(p['id'])
        break
" 2>/dev/null || echo "")

if [ -z "$PROJECT_ID" ]; then
  CREATE_PROJ=$(curl -sf -b /tmp/langfuse-cookies -X POST "$LANGFUSE_URL/api/projects" \
    -H "Content-Type: application/json" \
    -d "{\"name\": \"$PROJECT_NAME\"}" 2>/dev/null)
  PROJECT_ID=$(echo "$CREATE_PROJ" | python3 -c "import sys,json; print(json.load(sys.stdin).get('id',''))" 2>/dev/null || echo "")
fi

if [ -z "$PROJECT_ID" ]; then
  echo "  ✗ Failed to create project. Generate keys manually via the UI."
  exit 1
fi
echo "  ✓ Project ID: $PROJECT_ID"

# ---------------------------------------------------------------
# Generate API keys
# ---------------------------------------------------------------
echo "  Generating API keys..."
KEYS_RESPONSE=$(curl -sf -b /tmp/langfuse-cookies -X POST \
  "$LANGFUSE_URL/api/projects/$PROJECT_ID/api-keys" \
  -H "Content-Type: application/json" \
  -d '{"note": "auto-generated by setup script"}' 2>/dev/null)

PUBLIC_KEY=$(echo "$KEYS_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('publicKey',''))" 2>/dev/null || echo "")
SECRET_KEY=$(echo "$KEYS_RESPONSE" | python3 -c "import sys,json; print(json.load(sys.stdin).get('secretKey',''))" 2>/dev/null || echo "")

if [ -z "$PUBLIC_KEY" ] || [ -z "$SECRET_KEY" ]; then
  echo "  ✗ Failed to generate API keys. Response:"
  echo "    $KEYS_RESPONSE"
  echo "  Generate keys manually via the UI."
  exit 1
fi
echo "  ✓ Public key: ${PUBLIC_KEY:0:20}..."

# ---------------------------------------------------------------
# Write keys to K8s secret
# ---------------------------------------------------------------
echo "  Writing keys to secret $SECRET_NAME..."
AUTH_TOKEN=$(echo -n "$PUBLIC_KEY:$SECRET_KEY" | base64)

kubectl create secret generic "$SECRET_NAME" \
  -n "$NAMESPACE" \
  --from-literal=LANGFUSE_PUBLIC_KEY="$PUBLIC_KEY" \
  --from-literal=LANGFUSE_SECRET_KEY="$SECRET_KEY" \
  --from-literal=LANGFUSE_AUTH_TOKEN="$AUTH_TOKEN" \
  --dry-run=client -o yaml | kubectl apply -f -

echo "  ✓ Secret updated with real credentials"

# ---------------------------------------------------------------
# Restart components to pick up new keys
# ---------------------------------------------------------------
echo "  Restarting agents and collector..."
kubectl rollout restart deployment -n agents 2>/dev/null || true
kubectl rollout restart deployment/otel-collector-opentelemetry-collector -n "$NAMESPACE" 2>/dev/null || true

echo ""
echo "  ✓ Langfuse API keys configured successfully!"
echo "    Public key: $PUBLIC_KEY"
echo "    Langfuse UI: kubectl port-forward svc/$LANGFUSE_SVC -n $NAMESPACE 3000:3000"

# Cleanup
rm -f /tmp/langfuse-cookies
