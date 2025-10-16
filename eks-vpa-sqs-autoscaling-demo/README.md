# EKS Vertical Pod Autoscaler (VPA) with SQS Queue-Based Scaling Demo

This demo showcases how **Vertical Pod Autoscaler (VPA)** and **KEDA** work together to provide both vertical and horizontal scaling based on SQS queue depth in Amazon EKS.

## Architecture Overview

```
SQS Queue → KEDA → Horizontal Pod Autoscaler → Deployment
    ↓                                              ↓
    └─────────────────────────────────────→ VPA (adjusts resources)
```

## Key Components

- **VPA**: Automatically adjusts CPU and memory requests/limits based on actual usage
- **KEDA**: Scales pods horizontally based on SQS queue depth
- **SQS Consumer**: Python application that processes messages with CPU/memory intensive operations
- **Namespace**: `vpa-sqs-scaling-demo` - isolated environment for the demo

## Prerequisites

- EKS cluster with kubectl access
- AWS CLI configured
- Docker installed
- Helm installed
- jq installed (for JSON parsing)

## Quick Start

### 1. Setup Infrastructure
```bash
chmod +x *.sh
./setup.sh
```

### 2. Install VPA
```bash
./install-vpa.sh
```

### 3. Install KEDA
```bash
./install-keda.sh
```

### 4. Deploy Application
```bash
./deploy.sh
```

### 5. Test Scaling
```bash
./test-scaling.sh
```

### 6. Monitor (Optional)
```bash
./monitor.sh
```

## Demo Flow for Customer Presentation

### Phase 1: Initial State (2 minutes)
```bash
# Show initial deployment
kubectl get pods -n vpa-sqs-scaling-demo
kubectl describe vpa sqs-consumer-vpa -n vpa-sqs-scaling-demo
```

**Key Points:**
- Single pod with minimal resources (100m CPU, 64Mi memory)
- VPA in "Auto" mode for automatic resource adjustment
- No queue messages, no scaling activity

### Phase 2: VPA Recommendations (5 minutes)
```bash
# Send moderate load
aws sqs send-message --queue-url $(aws sqs get-queue-url --queue-name vpa-demo-queue --query QueueUrl --output text) --message-body "Test message" --region us-west-2

# Monitor VPA recommendations
watch kubectl describe vpa sqs-consumer-vpa -n vpa-sqs-scaling-demo
```

**Key Points:**
- VPA analyzes actual resource usage
- Provides recommendations for CPU and memory
- Shows target, lower bound, and upper bound values

### Phase 3: Horizontal Scaling (5 minutes)
```bash
# Send high load to trigger KEDA scaling
for i in {1..50}; do
  aws sqs send-message --queue-url $(aws sqs get-queue-url --queue-name vpa-demo-queue --query QueueUrl --output text) --message-body "Load test message $i" --region us-west-2
done

# Watch horizontal scaling
watch kubectl get pods -n vpa-sqs-scaling-demo
```

**Key Points:**
- KEDA detects queue depth > 5 messages
- Creates HPA to scale deployment horizontally
- New pods are created with VPA-recommended resources

### Phase 4: Combined Scaling (5 minutes)
```bash
# Monitor both VPA and HPA working together
./monitor.sh
```

**Key Points:**
- VPA adjusts resources on new pods created by KEDA
- Horizontal scaling handles load spikes
- Vertical scaling optimizes resource efficiency
- Both systems work independently but complementarily

### Phase 5: Scale Down (3 minutes)
```bash
# Purge queue to trigger scale down
aws sqs purge-queue --queue-url $(aws sqs get-queue-url --queue-name vpa-demo-queue --query QueueUrl --output text) --region us-west-2

# Watch scale down
watch kubectl get pods -n vpa-sqs-scaling-demo
```

**Key Points:**
- KEDA scales down when queue is empty
- VPA recommendations persist for future scaling
- Demonstrates complete scaling lifecycle

## Key Demonstration Points

### 1. VPA Benefits
- **Automatic Resource Optimization**: No manual tuning required
- **Cost Efficiency**: Right-sizing prevents over-provisioning
- **Performance**: Prevents resource starvation
- **Continuous Learning**: Adapts to changing workload patterns

### 2. KEDA Benefits
- **Event-Driven Scaling**: Scales based on actual queue depth
- **Zero-to-N Scaling**: Can scale to zero when no messages
- **Multiple Triggers**: Supports 50+ scalers (SQS, Kafka, etc.)
- **Cloud Native**: Kubernetes-native implementation

### 3. Combined Benefits
- **Multi-Dimensional Scaling**: Both vertical and horizontal
- **Workload Adaptive**: Handles both resource and load changes
- **Cost Optimized**: Efficient resource utilization
- **Production Ready**: Battle-tested in enterprise environments

## Monitoring Commands

```bash
# Pod status
kubectl get pods -n vpa-sqs-scaling-demo -o wide

# VPA recommendations
kubectl describe vpa sqs-consumer-vpa -n vpa-sqs-scaling-demo

# HPA status
kubectl get hpa -n vpa-sqs-scaling-demo

# KEDA scaler status
kubectl get scaledobject -n vpa-sqs-scaling-demo

# Queue depth
aws sqs get-queue-attributes --queue-url $(aws sqs get-queue-url --queue-name vpa-demo-queue --query QueueUrl --output text) --attribute-names ApproximateNumberOfMessages --query 'Attributes.ApproximateNumberOfMessages' --output text

# Resource usage
kubectl top pods -n vpa-sqs-scaling-demo
```

## Troubleshooting

### VPA Not Providing Recommendations
```bash
# Check VPA components
kubectl get pods -n kube-system | grep vpa

# Check VPA logs
kubectl logs -n kube-system deployment/vpa-recommender
```

### KEDA Not Scaling
```bash
# Check KEDA components
kubectl get pods -n keda

# Check ScaledObject status
kubectl describe scaledobject sqs-consumer-scaler -n vpa-sqs-scaling-demo

# Check KEDA logs
kubectl logs -n keda deployment/keda-operator
```

### Application Issues
```bash
# Check pod logs
kubectl logs -n vpa-sqs-scaling-demo deployment/sqs-consumer

# Check service account permissions
kubectl describe sa sqs-consumer-sa -n vpa-sqs-scaling-demo
```

## Cleanup

```bash
./cleanup.sh
```

## Files Overview

- `app.py` - SQS consumer application with CPU/memory intensive processing
- `Dockerfile` - Container image definition
- `01-namespace.yaml` - Kubernetes namespace
- `02-service-account.yaml` - IAM service account for SQS access
- `03-deployment.yaml` - Application deployment
- `04-vpa.yaml` - Vertical Pod Autoscaler configuration
- `05-keda-scaledobject.yaml` - KEDA scaling configuration
- `setup.sh` - Infrastructure setup script
- `install-vpa.sh` - VPA installation script
- `install-keda.sh` - KEDA installation script
- `deploy.sh` - Application deployment script
- `test-scaling.sh` - Scaling test script
- `monitor.sh` - Real-time monitoring script
- `cleanup.sh` - Resource cleanup script

## Customer Value Proposition

1. **Reduced Operational Overhead**: Automatic resource management
2. **Cost Optimization**: Right-sizing and efficient scaling
3. **Improved Performance**: Prevents resource bottlenecks
4. **Production Ready**: Enterprise-grade scaling solutions
5. **Cloud Native**: Kubernetes-native implementations
