#!/bin/bash
# Deployment script for NGINX Ingress Scalable Client Routing

set -e

# Colors for output
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[$(date +'%H:%M:%S')] WARNING:${NC} $1"
}

error() {
    echo -e "${RED}[$(date +'%H:%M:%S')] ERROR:${NC} $1"
}

echo "🚀 NGINX Ingress Scalable Client Routing - Deployment"
echo "====================================================="
echo

# Check prerequisites
log "Checking prerequisites..."

# Check kubectl
if ! command -v kubectl &> /dev/null; then
    error "kubectl is not installed or not in PATH"
    exit 1
fi

# Check cluster connection
if ! kubectl cluster-info &> /dev/null; then
    error "Cannot connect to Kubernetes cluster"
    exit 1
fi

log "✅ Prerequisites check passed"

# Check NGINX Ingress Controller
log "Checking NGINX Ingress Controller..."
if ! kubectl get pods -n ingress-nginx -l app.kubernetes.io/component=controller &> /dev/null; then
    warn "NGINX Ingress Controller not found"
    echo "Installing NGINX Ingress Controller..."
    
    kubectl apply -f https://raw.githubusercontent.com/kubernetes/ingress-nginx/controller-v1.8.1/deploy/static/provider/cloud/deploy.yaml
    
    log "Waiting for NGINX Ingress Controller to be ready..."
    kubectl wait --namespace ingress-nginx \
      --for=condition=ready pod \
      --selector=app.kubernetes.io/component=controller \
      --timeout=300s
    
    log "✅ NGINX Ingress Controller installed"
else
    log "✅ NGINX Ingress Controller found"
fi

# Deploy infrastructure
log "Deploying scalable routing infrastructure..."
kubectl apply -f infrastructure.yaml

# Wait for router service
log "Waiting for router service to be ready..."
kubectl wait --for=condition=ready pod -l app=client-router -n client-demo --timeout=120s

# Create sample client pods for testing
log "Creating sample client pods (1-5)..."
for i in {1..5}; do
    cat <<EOF | kubectl apply -f - > /dev/null
apiVersion: apps/v1
kind: Deployment
metadata:
  name: client-pod-$i
  namespace: client-demo
  labels:
    app: client-pod-$i
spec:
  replicas: 1
  selector:
    matchLabels:
      app: client-pod-$i
  template:
    metadata:
      labels:
        app: client-pod-$i
    spec:
      containers:
      - name: app
        image: nginx:alpine
        ports:
        - containerPort: 80
        resources:
          requests:
            memory: "32Mi"
            cpu: "25m"
          limits:
            memory: "64Mi"
            cpu: "50m"
        volumeMounts:
        - name: html
          mountPath: /usr/share/nginx/html
      volumes:
      - name: html
        configMap:
          name: client-pod-$i-html
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: client-pod-$i-html
  namespace: client-demo
data:
  index.html: |
    {"client_id": "$i", "pod_name": "client-pod-$i", "message": "Request processed by client-pod-$i", "timestamp": "$(date -Iseconds)"}
---
apiVersion: v1
kind: Service
metadata:
  name: client-pod-$i
  namespace: client-demo
  labels:
    app: client-pod-$i
spec:
  selector:
    app: client-pod-$i
  ports:
  - port: 80
    targetPort: 80
EOF
done

# Wait for sample pods
log "Waiting for sample pods to be ready..."
sleep 30

# Get ingress URL
log "Getting ingress URL..."
INGRESS_URL=""
for i in {1..30}; do
    # Try hostname first (AWS ELB)
    INGRESS_URL=$(kubectl get ingress -n client-demo scalable-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    # If no hostname, try IP (other cloud providers)
    if [ -z "$INGRESS_URL" ]; then
        INGRESS_URL=$(kubectl get ingress -n client-demo scalable-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    fi
    if [ -n "$INGRESS_URL" ]; then
        break
    fi
    sleep 10
done

echo
echo "🎉 DEPLOYMENT COMPLETE!"
echo "======================"
echo
echo "📊 Infrastructure Status:"
kubectl get pods,svc,ingress -n client-demo
echo
echo "🌐 Access Information:"
if [ -n "$INGRESS_URL" ]; then
    echo "   Ingress URL: http://$INGRESS_URL"
    echo
    echo "🧪 Test Commands:"
    echo "   curl -H 'X-Client-Id: 1' http://$INGRESS_URL"
    echo "   curl -H 'X-Client-Id: 2' http://$INGRESS_URL"
    echo
    echo "🚀 Run Demo:"
    echo "   ./demo.sh"
else
    warn "Ingress URL not yet available. Check status with:"
    echo "   kubectl get ingress -n client-demo scalable-ingress"
fi

echo
log "✅ Deployment successful!"
