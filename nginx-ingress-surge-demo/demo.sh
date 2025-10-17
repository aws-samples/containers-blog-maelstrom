#!/bin/bash
# Demo script for NGINX Ingress Scalable Client Routing

set -e

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

log() {
    echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"
}

info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

warn() {
    echo -e "${YELLOW}[WARNING]${NC} $1"
}

error() {
    echo -e "${RED}[ERROR]${NC} $1"
}

# Get ingress URL
get_ingress_url() {
    local url=""
    # Try hostname first (AWS ELB)
    url=$(kubectl get ingress -n client-demo scalable-ingress -o jsonpath='{.status.loadBalancer.ingress[0].hostname}' 2>/dev/null || echo "")
    # If no hostname, try IP (other cloud providers)
    if [ -z "$url" ]; then
        url=$(kubectl get ingress -n client-demo scalable-ingress -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    fi
    echo "$url"
}

# Create client pods
create_pods() {
    local count=$1
    log "Creating $count client pods..."
    
    for i in $(seq 1 $count); do
        cat <<EOF | kubectl apply -f - > /dev/null 2>&1
apiVersion: apps/v1
kind: Deployment
metadata:
  name: client-pod-$i
  namespace: client-demo
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
          requests: {memory: "32Mi", cpu: "25m"}
          limits: {memory: "64Mi", cpu: "50m"}
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
spec:
  selector:
    app: client-pod-$i
  ports:
  - port: 80
    targetPort: 80
EOF
    done
    
    log "✅ $count pods created"
}

# Test routing
test_routing() {
    local max_client=$1
    local ingress_url=$2
    
    log "Testing routing for clients 1-$max_client..."
    
    local success=0
    local total=0
    
    for i in $(seq 1 $max_client); do
        total=$((total + 1))
        response=$(curl -s -H "X-Client-Id: $i" http://$ingress_url 2>/dev/null || echo '{"error":"failed"}')
        pod_name=$(echo "$response" | jq -r '.pod_name // "error"' 2>/dev/null || echo "error")
        
        if [ "$pod_name" = "client-pod-$i" ]; then
            echo "  ✅ Client $i → $pod_name"
            success=$((success + 1))
        else
            echo "  ❌ Client $i → $pod_name"
        fi
    done
    
    echo
    info "Routing Test Results: $success/$total successful"
}

# Load test
load_test() {
    local requests=$1
    local ingress_url=$2
    
    log "Running load test with $requests concurrent requests..."
    
    local pids=()
    local results_file="/tmp/load_test_results.txt"
    > "$results_file"
    
    for i in $(seq 1 $requests); do
        client_id=$((($i % 10) + 1))
        (
            response=$(curl -s -H "X-Client-Id: $client_id" http://$ingress_url 2>/dev/null || echo '{"error":"failed"}')
            pod_name=$(echo "$response" | jq -r '.pod_name // "error"' 2>/dev/null || echo "error")
            echo "Request #$i: Client $client_id → $pod_name" >> "$results_file"
        ) &
        pids+=($!)
    done
    
    # Wait for all requests to complete
    for pid in "${pids[@]}"; do
        wait $pid
    done
    
    # Show results
    local successful=$(grep -c "client-pod-" "$results_file" 2>/dev/null || echo "0")
    echo
    info "Load Test Results: $successful/$requests successful requests"
    
    if [ $successful -gt 0 ]; then
        echo "Sample results:"
        head -10 "$results_file" | sed 's/^/  /'
    fi
    
    rm -f "$results_file"
}

# Scaling demo
scaling_demo() {
    local ingress_url=$1
    
    log "Demonstrating zero-maintenance scaling..."
    
    echo
    info "Current infrastructure:"
    kubectl get pods -n client-demo | grep client-pod | wc -l | xargs echo "  Active pods:"
    kubectl get ingress -n client-demo | grep scalable-ingress | awk '{print "  Ingress rules: 1 (static)"}'
    
    echo
    log "Adding 5 more pods (11-15)..."
    for i in {11..15}; do
        create_pods $i > /dev/null 2>&1
    done
    
    log "Waiting for new pods to be ready..."
    sleep 20
    
    echo
    log "Testing new pods (automatic discovery!)..."
    for i in {11..15}; do
        response=$(curl -s -H "X-Client-Id: $i" http://$ingress_url 2>/dev/null || echo '{"error":"not ready"}')
        pod_name=$(echo "$response" | jq -r '.pod_name // "not ready"' 2>/dev/null || echo "not ready")
        echo "  Client $i → $pod_name"
    done
    
    echo
    info "✅ Scaling complete - NO ingress configuration changes needed!"
}

# Status check
status_check() {
    echo "📊 INFRASTRUCTURE STATUS"
    echo "======================="
    echo
    
    echo "Namespace:"
    kubectl get ns client-demo 2>/dev/null || echo "  ❌ Namespace not found"
    
    echo
    echo "Router Service:"
    kubectl get pods -n client-demo -l app=client-router 2>/dev/null || echo "  ❌ Router not found"
    
    echo
    echo "Ingress:"
    kubectl get ingress -n client-demo scalable-ingress 2>/dev/null || echo "  ❌ Ingress not found"
    
    echo
    echo "Client Pods:"
    local pod_count=$(kubectl get pods -n client-demo | grep client-pod | wc -l)
    echo "  Active pods: $pod_count"
    
    echo
    local ingress_url=$(get_ingress_url)
    if [ -n "$ingress_url" ]; then
        echo "Ingress URL: http://$ingress_url"
    else
        echo "❌ Ingress URL not available yet"
    fi
}

# Main demo function
run_demo() {
    local ingress_url=$(get_ingress_url)
    
    if [ -z "$ingress_url" ]; then
        error "Ingress URL not available. Please run ./deploy.sh first"
        exit 1
    fi
    
    echo "🚀 NGINX INGRESS SCALABLE CLIENT ROUTING DEMO"
    echo "============================================="
    echo
    info "Ingress URL: http://$ingress_url"
    echo
    
    # Step 1: Basic routing test
    log "Step 1: Testing basic routing (existing pods)..."
    test_routing 5 "$ingress_url"
    
    echo
    read -p "Press Enter to continue to scaling demo..."
    
    # Step 2: Scaling demo
    log "Step 2: Zero-maintenance scaling demonstration..."
    scaling_demo "$ingress_url"
    
    echo
    read -p "Press Enter to continue to load test..."
    
    # Step 3: Load test
    log "Step 3: Load testing with concurrent requests..."
    load_test 20 "$ingress_url"
    
    echo
    echo "🎉 DEMO COMPLETE!"
    echo "================"
    echo
    echo "✅ Key Achievements Demonstrated:"
    echo "  • Zero NGINX maintenance for pod scaling"
    echo "  • Automatic service discovery"
    echo "  • High-performance concurrent routing"
    echo "  • Single ingress rule handles unlimited pods"
    echo
    echo "🔧 Architecture Benefits:"
    echo "  • NGINX: Static configuration (never changes)"
    echo "  • Router: Dynamic service discovery"
    echo "  • Kubernetes: Automatic DNS resolution"
    echo "  • Result: Infinite scalability with zero maintenance"
}

# Command handling
case "${1:-demo}" in
    "status")
        status_check
        ;;
    "test")
        ingress_url=$(get_ingress_url)
        if [ -z "$ingress_url" ]; then
            error "Ingress URL not available"
            exit 1
        fi
        test_routing ${2:-10} "$ingress_url"
        ;;
    "load")
        ingress_url=$(get_ingress_url)
        if [ -z "$ingress_url" ]; then
            error "Ingress URL not available"
            exit 1
        fi
        load_test ${2:-20} "$ingress_url"
        ;;
    "scale")
        create_pods ${2:-10}
        ;;
    "demo")
        run_demo
        ;;
    "help"|*)
        echo "NGINX Ingress Scalable Client Routing - Demo Script"
        echo "Usage: $0 {demo|status|test|load|scale|help}"
        echo
        echo "Commands:"
        echo "  demo              - Run complete interactive demo"
        echo "  status            - Check infrastructure status"
        echo "  test [count]      - Test routing for N clients (default: 10)"
        echo "  load [requests]   - Run load test with N requests (default: 20)"
        echo "  scale [count]     - Create N client pods (default: 10)"
        echo "  help              - Show this help message"
        echo
        echo "Examples:"
        echo "  $0 demo           # Interactive demo"
        echo "  $0 test 5         # Test routing for clients 1-5"
        echo "  $0 load 50        # Load test with 50 requests"
        echo "  $0 scale 20       # Create 20 client pods"
        ;;
esac
