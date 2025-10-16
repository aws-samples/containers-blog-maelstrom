# 🚀 Complete EKS Scaling Solutions

This repository contains two comprehensive, production-ready scaling solutions for Amazon EKS that demonstrate different autoscaling patterns and use cases.

## 📦 Solutions Overview

### 1. VPA SQS Scaling Solution (`vpa-sqs-scaling-demo/`)
**Vertical Pod Autoscaling based on SQS message load**

- **Pattern**: Vertical scaling (CPU/Memory optimization)
- **Trigger**: SQS queue depth and processing load
- **Use Case**: Variable workload intensity requiring resource optimization
- **Key Features**:
  - Automatic CPU/memory scaling based on workload
  - SQS integration with AWS SDK
  - Resource optimization and cost efficiency
  - Production-ready configuration

### 2. MSK Microbatch Processing Solution (`msk-microbatch-demo/`)
**Horizontal Pod Autoscaling with KEDA based on Kafka queue depth**

- **Pattern**: Horizontal scaling (Pod count optimization)
- **Trigger**: Kafka consumer group lag
- **Use Case**: High-throughput message processing with variable load
- **Key Features**:
  - Multi-partition fanout processing (8 partitions → 24 pods)
  - Microbatch processing (10 messages per batch)
  - KEDA auto-scaling based on consumer group lag
  - MSK integration with SCRAM authentication
  - Fault-tolerant offset management

## 🎯 When to Use Each Solution

### Use VPA Solution When:
- ✅ Workload intensity varies but pod count can remain stable
- ✅ You want to optimize resource allocation and reduce costs
- ✅ Applications have predictable scaling patterns
- ✅ Memory or CPU requirements change based on data volume

### Use MSK Solution When:
- ✅ You need to process high-volume message streams
- ✅ Workload can be parallelized across multiple pods
- ✅ Queue depth varies significantly over time
- ✅ You want fault-tolerant, distributed processing

## 🏗️ Architecture Comparison

| Aspect | VPA Solution | MSK Solution |
|--------|-------------|--------------|
| **Scaling Type** | Vertical (Resources) | Horizontal (Pod Count) |
| **Trigger Source** | SQS Queue Depth | Kafka Consumer Lag |
| **Scaling Speed** | Moderate (Pod restart) | Fast (New pods) |
| **Resource Efficiency** | High (Right-sizing) | Variable (Fixed pod size) |
| **Fault Tolerance** | Single pod failure | Multi-pod resilience |
| **Best For** | Variable intensity | Variable volume |

## 📋 Prerequisites

### Common Requirements
- Amazon EKS cluster (v1.24+)
- kubectl configured for your cluster
- AWS CLI configured with appropriate permissions
- Metrics Server installed on the cluster

### VPA Solution Specific
- Vertical Pod Autoscaler installed
- Amazon SQS queue
- IAM permissions for SQS access

### MSK Solution Specific
- KEDA installed on the cluster
- Amazon MSK cluster with SCRAM authentication
- IAM permissions for MSK access

## 🚀 Quick Start

### Deploy VPA Solution
```bash
cd vpa-sqs-scaling-demo/
./setup.sh
./deploy.sh
./monitor.sh
```

### Deploy MSK Solution
```bash
cd msk-microbatch-demo/
./setup-msk.sh
./deploy.sh
./monitor.sh
```

## 📊 Monitoring and Observability

Both solutions include comprehensive monitoring capabilities:

### VPA Solution Monitoring
- Pod resource utilization metrics
- SQS queue depth and message processing rate
- VPA recommendations and scaling events
- Application performance metrics

### MSK Solution Monitoring
- Consumer group lag metrics
- Pod scaling events and performance
- Message processing throughput
- Partition distribution and load balancing

## 🔧 Configuration Options

### VPA Configuration
- **updateMode**: `Auto` (default) or `Off` for recommendation-only
- **resourcePolicy**: CPU and memory bounds and scaling behavior
- **targetCPUUtilizationPercentage**: Threshold for scaling decisions

### KEDA Configuration
- **pollingInterval**: How often to check metrics (default: 30s)
- **cooldownPeriod**: Time to wait before scaling down (default: 300s)
- **minReplicaCount**: Minimum number of pods (default: 1)
- **maxReplicaCount**: Maximum number of pods (default: 10)

## 🛡️ Security Considerations

### IAM Permissions
Both solutions use IAM roles for service account (IRSA) for secure AWS service access:

- **VPA Solution**: Requires SQS read/write permissions
- **MSK Solution**: Requires MSK cluster access and SCRAM authentication

### Network Security
- Security groups configured for MSK access
- VPC endpoints for private AWS service communication
- Network policies for pod-to-pod communication

## 💰 Cost Optimization

### VPA Solution Cost Benefits
- **Right-sizing**: Eliminates over-provisioning
- **Resource efficiency**: Reduces waste by 20-40%
- **Automatic optimization**: Continuous cost optimization

### MSK Solution Cost Benefits
- **Scale-to-zero**: Scales down to minimum during low load
- **Efficient processing**: Batch processing reduces overhead
- **Resource sharing**: Multiple consumers share cluster resources

## 🔍 Troubleshooting

### Common Issues

#### VPA Not Scaling
1. Check VPA status: `kubectl describe vpa -n scaling-demo`
2. Verify metrics server: `kubectl top pods -n scaling-demo`
3. Check resource requests/limits in deployment

#### KEDA Not Scaling
1. Check KEDA operator logs: `kubectl logs -n keda-system -l app=keda-operator`
2. Verify ScaledObject status: `kubectl describe scaledobject -n msk-demo`
3. Check MSK connectivity and authentication

#### MSK Connection Issues
1. Verify security group rules
2. Check SCRAM credentials in secret
3. Test connectivity from pod: `kubectl exec -it <pod> -- telnet <msk-endpoint> 9096`

### Performance Tuning

#### VPA Optimization
- Adjust `updateMode` based on workload stability
- Fine-tune resource policies for optimal scaling
- Monitor recommendation accuracy and adjust bounds

#### MSK Optimization
- Tune batch size based on message processing time
- Adjust partition count for optimal parallelization
- Configure consumer group settings for fault tolerance

## 📚 Additional Resources

- [Amazon EKS User Guide](https://docs.aws.amazon.com/eks/latest/userguide/)
- [Vertical Pod Autoscaler Documentation](https://github.com/kubernetes/autoscaler/tree/master/vertical-pod-autoscaler)
- [KEDA Documentation](https://keda.sh/docs/)
- [Amazon MSK Developer Guide](https://docs.aws.amazon.com/msk/latest/developerguide/)
- [Amazon SQS Developer Guide](https://docs.aws.amazon.com/sqs/latest/dg/)

## 🤝 Contributing

1. Fork the repository
2. Create a feature branch
3. Make your changes
4. Add tests and documentation
5. Submit a pull request

## 📄 License

This project is licensed under the MIT-0 License - see the [LICENSE](LICENSE) file for details.

---

**Note**: These solutions are production-ready but should be tested in your specific environment before deployment. Always follow your organization's security and operational guidelines.
