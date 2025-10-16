# MSK Microbatch Processing with KEDA Demo

## Overview

This demo showcases **Horizontal Pod Autoscaling (HPA)** with **Amazon MSK (Managed Streaming for Apache Kafka)** using **KEDA (Kubernetes Event-driven Autoscaling)**. The solution demonstrates multi-partition fanout processing with automatic scaling based on Kafka queue depth.

## Architecture

```
MSK Topic (8 partitions) → Multiple Consumer Pods → KEDA (Horizontal Scaling) → Microbatch Processing
```

### Components

- **Amazon MSK**: Managed Kafka cluster with SASL/SCRAM authentication
- **Consumer Application**: Python application processing messages in configurable microbatches
- **KEDA**: Event-driven autoscaler monitoring Kafka consumer group lag
- **Multi-Partition Fanout**: Multiple consumer pods per partition for maximum throughput

## Prerequisites

### Required Infrastructure
- **Amazon EKS Cluster** (v1.24+)
- **Amazon MSK Cluster** with SASL/SCRAM authentication enabled
- **VPC with private subnets** connecting EKS and MSK
- **Security Groups** allowing EKS to MSK communication (port 9096)
- **kubectl** configured to access your EKS cluster

### Required Add-ons

1. **KEDA Controller** - Install using:
   ```bash
   kubectl apply -f https://github.com/kedacore/keda/releases/download/v2.12.0/keda-2.12.0.yaml
   ```

2. **Metrics Server** (usually pre-installed):
   ```bash
   kubectl apply -f https://github.com/kubernetes-sigs/metrics-server/releases/latest/download/components.yaml
   ```

### AWS Services Setup

#### 1. MSK Cluster Configuration
```bash
# Create MSK cluster with SCRAM authentication
aws kafka create-cluster \
  --cluster-name msk-demo-cluster \
  --broker-node-group-info file://broker-info.json \
  --client-authentication file://client-auth.json \
  --kafka-version "3.7.x"
```

#### 2. SCRAM Credentials
```bash
# Create secret in AWS Secrets Manager (must have AmazonMSK_ prefix)
aws secretsmanager create-secret \
  --name AmazonMSK_demo-credentials \
  --description "MSK SCRAM credentials" \
  --secret-string '{"username":"kafka-user","password":"your-secure-password"}' \
  --kms-key-id your-kms-key-id

# Associate secret with MSK cluster
aws kafka batch-associate-scram-secret \
  --cluster-arn your-cluster-arn \
  --secret-arn-list your-secret-arn
```

### Network Configuration

#### Security Group Rules
```bash
# MSK Security Group - Allow EKS access
aws ec2 authorize-security-group-ingress \
  --group-id sg-msk-cluster \
  --protocol tcp \
  --port 9096 \
  --source-group sg-eks-cluster
```

## Quick Start

### 1. Clone and Navigate
```bash
git clone <repository-url>
cd containers-blog-maelstrom/msk-microbatch-demo
```

### 2. Configure Credentials
Update `03-secret.yaml` with your MSK bootstrap servers and credentials:
```yaml
stringData:
  username: "kafka-user"
  password: "your-password"
  bootstrap-servers: "your-msk-bootstrap-servers:9096"
```

### 3. Deploy the Solution
```bash
# Deploy all components
./deploy.sh

# Or deploy step by step
kubectl apply -f 01-namespace.yaml
kubectl apply -f 02-configmap.yaml
kubectl apply -f 03-secret.yaml
kubectl apply -f 04-service-account.yaml
kubectl apply -f 05-deployment.yaml
kubectl apply -f 07-keda-scaledobject.yaml
```

### 4. Run the Demo
```bash
# Run comprehensive multi-partition demo
./customer-demo.sh

# Monitor scaling and processing
./monitor.sh
```

## Configuration

### Application Configuration (ConfigMap)
```yaml
data:
  BATCH_SIZE: "10"              # Messages per microbatch
  PROCESS_TIME_SECONDS: "2"     # Processing time per message
  KAFKA_TOPIC: "microbatch-topic"
  CONSUMER_GROUP: "batch-processor-group"
```

### KEDA ScaledObject Configuration
```yaml
spec:
  scaleTargetRef:
    name: kafka-batch-processor
  minReplicaCount: 1
  maxReplicaCount: 24           # 3 pods per partition (8 partitions)
  triggers:
  - type: kafka
    metadata:
      bootstrapServers: "your-msk-brokers:9096"
      consumerGroup: "batch-processor-group"
      topic: "microbatch-topic"
      lagThreshold: '3'          # Scale when lag > 3 messages
      activationLagThreshold: '1' # Activate scaling when lag > 1
      sasl: scram_sha512
      tls: enable
```

## Demo Scenarios

### Scenario 1: Multi-Partition Fanout
- **Architecture**: 8 partitions → 24 consumer pods (3 per partition)
- **Load**: 1000+ messages distributed across partitions
- **Scaling**: KEDA scales based on aggregate consumer group lag
- **Processing**: Microbatches of 10 messages with fault-tolerant commits

### Scenario 2: High-Throughput Processing
- **Load Pattern**: Burst of messages to specific partitions
- **Expected Behavior**: Rapid horizontal scaling of consumer pods
- **Fault Tolerance**: Automatic partition rebalancing on pod failures

### Scenario 3: Cost Optimization
- **Idle State**: Scales down to 1 pod when no messages
- **Load Response**: Scales up within seconds of message arrival
- **Resource Efficiency**: Only pay for compute when processing messages

## Monitoring

### Key Metrics to Monitor

#### KEDA Metrics
```bash
# Check KEDA ScaledObject status
kubectl get scaledobject -n msk-microbatch-demo

# View HPA created by KEDA
kubectl get hpa -n msk-microbatch-demo

# KEDA operator logs
kubectl logs -n keda deployment/keda-operator
```

#### Kafka Consumer Metrics
```bash
# Consumer group lag
kubectl run kafka-admin --image=confluentinc/cp-kafka:latest --rm -i -n msk-microbatch-demo --restart=Never -- \
  kafka-consumer-groups --bootstrap-server your-brokers:9096 \
  --command-config /tmp/client.properties \
  --describe --group batch-processor-group

# Topic partition details
kubectl run kafka-admin --image=confluentinc/cp-kafka:latest --rm -i -n msk-microbatch-demo --restart=Never -- \
  kafka-topics --bootstrap-server your-brokers:9096 \
  --command-config /tmp/client.properties \
  --describe --topic microbatch-topic
```

#### Application Metrics
```bash
# Pod resource usage
kubectl top pods -n msk-microbatch-demo

# Processing logs
kubectl logs -f -l app=kafka-batch-processor -n msk-microbatch-demo

# Scaling events
kubectl get events -n msk-microbatch-demo --sort-by='.lastTimestamp'
```

### CloudWatch Integration
- **MSK Metrics**: Broker CPU, disk usage, network throughput
- **Consumer Lag**: Per-partition consumer lag metrics
- **Custom Metrics**: Application-specific processing metrics

## Troubleshooting

### Common Issues

#### 1. KEDA Not Scaling
```bash
# Check KEDA operator status
kubectl get pods -n keda

# Verify ScaledObject configuration
kubectl describe scaledobject kafka-scaledobject -n msk-microbatch-demo

# Check HPA status
kubectl describe hpa -n msk-microbatch-demo
```

#### 2. MSK Connection Issues
```bash
# Test connectivity from pod
kubectl run kafka-test --image=confluentinc/cp-kafka:latest --rm -i -n msk-microbatch-demo --restart=Never -- \
  kafka-broker-api-versions --bootstrap-server your-brokers:9096 \
  --command-config /tmp/client.properties

# Check security group rules
aws ec2 describe-security-groups --group-ids your-msk-sg-id
```

#### 3. Authentication Problems
```bash
# Verify SCRAM secret association
aws kafka list-scram-secrets --cluster-arn your-cluster-arn

# Check pod logs for auth errors
kubectl logs -l app=kafka-batch-processor -n msk-microbatch-demo | grep -i auth
```

#### 4. Partition Assignment Issues
```bash
# Check consumer group status
kubectl logs -l app=kafka-batch-processor -n msk-microbatch-demo | grep -i "partition assignment"

# Verify topic partition count
kubectl run kafka-admin --image=confluentinc/cp-kafka:latest --rm -i -n msk-microbatch-demo --restart=Never -- \
  kafka-topics --bootstrap-server your-brokers:9096 \
  --command-config /tmp/client.properties \
  --list
```

### Debug Commands
```bash
# KEDA metrics
kubectl get --raw /apis/external.metrics.k8s.io/v1beta1/namespaces/msk-microbatch-demo/s0-kafka-microbatch-topic

# Pod resource requests/limits
kubectl describe pod -l app=kafka-batch-processor -n msk-microbatch-demo

# Network connectivity test
kubectl run netshoot --image=nicolaka/netshoot --rm -i -n msk-microbatch-demo --restart=Never -- \
  nc -zv your-msk-broker 9096
```

## Performance Tuning

### KEDA Configuration
```yaml
# Faster scaling response
pollingInterval: 15    # Check metrics every 15 seconds (default: 30)
cooldownPeriod: 60     # Wait 60 seconds before scaling down (default: 300)

# More aggressive scaling
triggers:
- type: kafka
  metadata:
    lagThreshold: '2'           # Lower threshold for faster scaling
    activationLagThreshold: '1'
```

### Consumer Application Tuning
```yaml
# Optimize batch processing
env:
- name: BATCH_SIZE
  value: "20"                   # Larger batches for higher throughput
- name: PROCESS_TIME_SECONDS
  value: "1"                    # Faster processing per message
```

### Kafka Topic Configuration
```bash
# Optimize topic for high throughput
kafka-configs --bootstrap-server your-brokers:9096 \
  --command-config /tmp/client.properties \
  --entity-type topics \
  --entity-name microbatch-topic \
  --alter --add-config min.insync.replicas=2,unclean.leader.election.enable=false
```

## Best Practices

### Scaling Strategy
- **Partition Design**: Use 8+ partitions for optimal parallelism
- **Consumer Groups**: One consumer group per application
- **Pod Distribution**: Target 2-3 pods per partition for fault tolerance
- **Resource Limits**: Set appropriate CPU/memory limits

### Fault Tolerance
- **Offset Management**: Manual commits after successful batch processing
- **Dead Letter Queues**: Handle poison messages appropriately
- **Circuit Breakers**: Implement retry logic with exponential backoff
- **Health Checks**: Proper liveness and readiness probes

### Security
- **SCRAM Authentication**: Use strong passwords and rotate regularly
- **TLS Encryption**: Enable in-transit encryption
- **Network Isolation**: Use private subnets and security groups
- **IAM Integration**: Use IRSA for AWS service access

### Cost Optimization
- **Right-sizing**: Monitor actual resource usage vs requests
- **Spot Instances**: Use for non-critical consumer workloads
- **Scaling Policies**: Tune KEDA thresholds for cost vs performance
- **Resource Requests**: Set appropriate requests to avoid over-provisioning

## Advanced Scenarios

### Multi-Tenant Processing
```yaml
# Separate consumer groups per tenant
spec:
  triggers:
  - type: kafka
    metadata:
      consumerGroup: "tenant-a-processors"
      lagThreshold: '5'
  - type: kafka
    metadata:
      consumerGroup: "tenant-b-processors"
      lagThreshold: '3'
```

### Cross-Region Replication
- Configure MSK cross-region replication
- Deploy consumers in multiple regions
- Implement failover logic

### Schema Evolution
- Use Confluent Schema Registry
- Implement backward-compatible message formats
- Version your consumer applications

## Cleanup

```bash
# Remove all resources
./cleanup.sh

# Or manually
kubectl delete namespace msk-microbatch-demo

# Clean up MSK resources (optional)
aws kafka delete-cluster --cluster-arn your-cluster-arn
```

## Files Structure

```
msk-microbatch-demo/
├── README.md                    # This comprehensive documentation
├── 01-namespace.yaml            # Kubernetes namespace
├── 02-configmap.yaml           # Application configuration
├── 03-secret.yaml              # MSK credentials and bootstrap servers
├── 04-service-account.yaml     # Service account
├── 05-deployment.yaml          # Consumer deployment
├── 07-keda-scaledobject.yaml   # KEDA scaling configuration
├── app.py                      # Kafka consumer application
├── requirements.txt            # Python dependencies
├── Dockerfile                  # Container image definition
├── customer-demo.sh            # Comprehensive demo script
├── deploy.sh                   # Deployment script
├── monitor.sh                  # Monitoring script
├── cleanup.sh                  # Cleanup script
├── setup-msk.sh               # MSK cluster setup script
└── run-demo.sh                 # Basic demo runner
```

## Integration Examples

### CloudWatch Dashboard
```json
{
  "widgets": [
    {
      "type": "metric",
      "properties": {
        "metrics": [
          ["AWS/Kafka", "ConsumerLag", "Consumer Group", "batch-processor-group"]
        ],
        "period": 300,
        "stat": "Average",
        "region": "us-west-2",
        "title": "Consumer Lag"
      }
    }
  ]
}
```

### Prometheus Monitoring
```yaml
# ServiceMonitor for Prometheus
apiVersion: monitoring.coreos.com/v1
kind: ServiceMonitor
metadata:
  name: kafka-consumer-metrics
spec:
  selector:
    matchLabels:
      app: kafka-batch-processor
  endpoints:
  - port: metrics
```

## Troubleshooting Guide

### Performance Issues
1. **High Consumer Lag**: Increase partition count or consumer pods
2. **Slow Processing**: Optimize batch size and processing logic
3. **Memory Issues**: Adjust JVM heap settings for Kafka clients
4. **Network Latency**: Ensure EKS and MSK are in same AZ

### Scaling Issues
1. **KEDA Not Responding**: Check metrics server and KEDA operator logs
2. **Pods Not Starting**: Verify resource quotas and node capacity
3. **Authentication Failures**: Validate SCRAM credentials and MSK association
4. **Network Connectivity**: Test security group rules and VPC configuration

This comprehensive documentation provides everything needed to deploy, configure, monitor, and troubleshoot the MSK microbatch processing solution with KEDA autoscaling.
