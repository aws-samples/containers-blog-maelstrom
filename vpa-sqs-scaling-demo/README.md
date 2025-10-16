# VPA SQS Scaling Demo

## Overview

This demo showcases **Vertical Pod Autoscaling (VPA)** with **Amazon SQS** integration on Amazon EKS. The solution demonstrates how VPA automatically adjusts CPU and memory resources for pods based on actual usage patterns while processing SQS messages.

## Architecture

```
SQS Queue → Consumer Pods → VPA (Vertical Scaling) → Resource Optimization
```

### Components

- **Amazon SQS**: Message queue with configurable message load
- **Consumer Application**: Python application that processes SQS messages
- **VPA (Vertical Pod Autoscaler)**: Automatically adjusts pod CPU/memory resources
- **CloudWatch**: Monitoring and observability

## Prerequisites

### Required Infrastructure
- **Amazon EKS Cluster** (v1.24+)
- **VPC with private subnets** for EKS worker nodes
- **IAM roles** with appropriate permissions
- **kubectl** configured to access your EKS cluster

### Required Add-ons
1. **VPA Controller** - Install using:
   ```bash
   kubectl apply -f https://github.com/kubernetes/autoscaler/releases/download/vertical-pod-autoscaler-0.13.0/vpa-v0.13.0.yaml
   ```

2. **AWS Load Balancer Controller** (optional, for ingress)
3. **EBS CSI Driver** (for persistent storage if needed)

### AWS Permissions
Your EKS worker nodes need the following IAM permissions:
- `sqs:ReceiveMessage`
- `sqs:DeleteMessage`
- `sqs:GetQueueAttributes`
- `cloudwatch:PutMetricData`

## Quick Start

### 1. Clone and Navigate
```bash
git clone <repository-url>
cd containers-blog-maelstrom/vpa-sqs-scaling-demo
```

### 2. Deploy the Solution
```bash
# Deploy all components
./deploy.sh

# Or deploy step by step
kubectl apply -f 01-namespace.yaml
kubectl apply -f 02-configmap.yaml
kubectl apply -f 03-secret.yaml
kubectl apply -f 04-service-account.yaml
kubectl apply -f 05-deployment.yaml
kubectl apply -f 06-vpa.yaml
```

### 3. Run the Demo
```bash
# Send messages to SQS to trigger VPA scaling
./run-demo.sh

# Monitor VPA recommendations and scaling
./monitor.sh
```

## Configuration

### Environment Variables (ConfigMap)
- `QUEUE_URL`: SQS queue URL
- `REGION`: AWS region
- `POLL_INTERVAL`: Message polling interval (seconds)
- `PROCESS_TIME`: Simulated processing time per message

### VPA Configuration
```yaml
spec:
  targetRef:
    apiVersion: apps/v1
    kind: Deployment
    name: sqs-consumer
  updatePolicy:
    updateMode: "Auto"  # Auto, Off, Initial
  resourcePolicy:
    containerPolicies:
    - containerName: consumer
      maxAllowed:
        cpu: 2
        memory: 4Gi
      minAllowed:
        cpu: 100m
        memory: 128Mi
```

## Demo Scenarios

### Scenario 1: Low Load
- **Messages**: 10-50 messages
- **Expected VPA**: Minimal CPU/memory recommendations
- **Behavior**: VPA maintains baseline resources

### Scenario 2: Medium Load
- **Messages**: 100-500 messages
- **Expected VPA**: Moderate CPU increase
- **Behavior**: VPA adjusts resources based on processing patterns

### Scenario 3: High Load
- **Messages**: 1000+ messages
- **Expected VPA**: Significant CPU/memory scaling
- **Behavior**: VPA maximizes resources within defined limits

## Monitoring

### Key Metrics to Watch
```bash
# VPA recommendations
kubectl describe vpa sqs-consumer-vpa -n vpa-sqs-scaling-demo

# Pod resource usage
kubectl top pods -n vpa-sqs-scaling-demo

# SQS queue depth
aws sqs get-queue-attributes --queue-url $QUEUE_URL --attribute-names ApproximateNumberOfMessages
```

### CloudWatch Metrics
- `AWS/SQS/ApproximateNumberOfMessages`
- `AWS/SQS/NumberOfMessagesReceived`
- `AWS/SQS/NumberOfMessagesDeleted`

## Troubleshooting

### Common Issues

1. **VPA Not Scaling**
   ```bash
   # Check VPA controller logs
   kubectl logs -n kube-system -l app=vpa-recommender
   
   # Verify VPA CRDs
   kubectl get crd | grep verticalpodautoscaler
   ```

2. **SQS Permission Errors**
   ```bash
   # Check pod logs
   kubectl logs -n vpa-sqs-scaling-demo -l app=sqs-consumer
   
   # Verify IAM role
   aws sts get-caller-identity
   ```

3. **Pod Resource Limits**
   ```bash
   # Check resource constraints
   kubectl describe pod -n vpa-sqs-scaling-demo -l app=sqs-consumer
   ```

### Debug Commands
```bash
# Check VPA status
kubectl get vpa -n vpa-sqs-scaling-demo

# View VPA events
kubectl get events -n vpa-sqs-scaling-demo --sort-by='.lastTimestamp'

# Monitor resource usage
watch kubectl top pods -n vpa-sqs-scaling-demo
```

## Best Practices

### VPA Configuration
- Set appropriate `minAllowed` and `maxAllowed` limits
- Use `updateMode: "Auto"` for production workloads
- Monitor VPA recommendations before enabling auto-updates

### Resource Management
- Define resource requests and limits in deployment
- Use quality of service classes (QoS) appropriately
- Monitor actual vs recommended resources

### SQS Integration
- Use dead letter queues for failed messages
- Implement exponential backoff for retries
- Monitor queue depth and processing rates

## Cleanup

```bash
# Remove all resources
./cleanup.sh

# Or manually
kubectl delete namespace vpa-sqs-scaling-demo
```

## Files Structure

```
vpa-sqs-scaling-demo/
├── README.md                 # This documentation
├── 01-namespace.yaml         # Kubernetes namespace
├── 02-configmap.yaml         # Application configuration
├── 03-secret.yaml           # AWS credentials (if needed)
├── 04-service-account.yaml  # Service account with IAM role
├── 05-deployment.yaml       # SQS consumer deployment
├── 06-vpa.yaml              # VPA configuration
├── app.py                   # SQS consumer application
├── requirements.txt         # Python dependencies
├── Dockerfile              # Container image definition
├── deploy.sh               # Deployment script
├── run-demo.sh             # Demo execution script
├── monitor.sh              # Monitoring script
└── cleanup.sh              # Cleanup script
```

## Advanced Configuration

### Custom VPA Policies
```yaml
resourcePolicy:
  containerPolicies:
  - containerName: consumer
    mode: Auto
    controlledResources: ["cpu", "memory"]
    controlledValues: RequestsAndLimits
```

### Multi-Container Pods
```yaml
spec:
  containers:
  - name: consumer
    # VPA will manage this container
  - name: sidecar
    # VPA can manage multiple containers
```

## Integration with Other AWS Services

- **CloudWatch Logs**: Centralized logging
- **X-Ray**: Distributed tracing
- **Parameter Store**: Configuration management
- **Secrets Manager**: Secure credential storage

## Performance Tuning

### VPA Tuning
- Adjust `recommender-interval` for faster recommendations
- Configure `updater-interval` for update frequency
- Set appropriate `memory-saver` thresholds

### Application Tuning
- Optimize message processing logic
- Implement connection pooling
- Use async processing where appropriate

## Security Considerations

- Use IAM roles for service accounts (IRSA)
- Encrypt SQS messages in transit and at rest
- Implement least privilege access policies
- Regular security scanning of container images

## Cost Optimization

- Monitor VPA recommendations vs actual usage
- Set appropriate resource limits to prevent over-provisioning
- Use Spot instances for non-critical workloads
- Implement queue-based scaling policies
