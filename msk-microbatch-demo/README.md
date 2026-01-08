# MSK EKS Microbatch Processing with Keda - Demo

## Introduction

This architecture demonstrates how to process variable transaction volumes with speed and cost efficiency. 

The solution combines **AWS MSK** (managed Kafka) for durable message streaming with **Amazon EKS** and **KEDA** for event-driven autoscaling. It delivers:

- **Massive parallelization** across Kafka partitions for high throughput
- **Responsive scaling** of processing capacity as soon as unprocessed messages increase
- **Message persistence and replay** for audit/compliance requirements
- **Ordering guarantees** via Kafka partition keys when needed
- **Multi-tenant isolation** using kafka topics and consumer groups for service providers managing multiple institutions
- **Managed services** (MSK, EKS) to reduce operational overhead
- **Built-in security** with IAM authentication and encryption

## Architecture Components

![Architecture Diagram](images/Architecture.png)

- **AWS MSK**: Managed Kafka cluster with IAM authentication and 24 partitions for parallelization
- **Amazon EKS**: Kubernetes cluster with automatic compute management
- **KEDA**: Event-driven autoscaler monitoring Kafka consumer lag (scales 0-20 replicas)
- **Consumer Application**: Microbatch processor with cooperative rebalancing for zero-downtime scaling
- **Producer Simulator**: Generates transaction loads to demonstrate elasticity
- **Prometheus + Grafana**: Observability stack for metrics and dashboards

## Tuning Autoscaling Behavior

Scaling responsiveness is configured using KEDA ScaledObject YAML. The key challenge is balancing **scaling speed** vs **stability** to avoid flapping:

- **Too reactive**: System becomes unstable, flapping up and down the number of pods
- **Too slow**: Messages accumulate in Kafka, increasing processing delays

Multiple factors add to scaling instability such as Kafka partition rebalancing when pods join or leave the consumer group, traffic variability, etc. Extra care should be taken to smooth out scaling and avoid a flapping system.

**Critical tuning steps:**

1. **Optimize partition rebalancing** by using cooperative rebalancing in the consumer app. 
During scale events, Kafka redistributes partition assignments across pods. With default "eager" rebalancing, all consumers pause processing, which dramatically reduces processing throughput and risks breaching SLA. This architecture uses **cooperative rebalancing**, allowing most pods to continue processing while only affected pods pause briefly, reducing the impact on processing throughput during scaling.

2. **Profile your application** to identify:
   - Peak processing capacity per pod (~100 msg/s in this demo)
   - Ramp-up time to reach peak capacity (~60 seconds in this demo)
   - Time it takes for partition rebalance to complete and consumers to pick up processing speed again (~60 seconds in this demo)

3. **Tune Keda timing settings**:
   Consider multiple configuration options for influencing scaling sensitivity:
   - **Pod initialReadinessDelay**: Allow time for new pods to ramp up before HPA considers them ready
   - **StabilizationWindowSeconds**: Consider metric values using a rolling window to smooth out fluctuations
   - **Scaling policy periodSeconds**: Define an upper budget for scaling and wait for a period of time to scale again after the budget is consumed

## Deployment Steps

### Prerequisites

- AWS CLI configured with appropriate credentials
- Docker installed and running
- Terraform >= 1.3
- kubectl
- jq

### Step 1: Deploy Infrastructure

Deploy the underlying infrastructure using Terraform:

```bash
./deploy-infra.sh
```

This creates:
- **VPC** with public/private subnets across 2 AZs
- **MSK cluster** with 2 brokers, 24 partitions, IAM authentication
- **EKS cluster** with Auto Mode for managed compute
- **IAM roles and policies** for Pod Identity (producer, consumer, KEDA)
- **Prometheus + Grafana** for observability (in cluster kube-prometheus-stack)
- **KEDA operator** for event-driven autoscaling

**Verify MSK bootstrap servers were added to .env:**
```bash
grep "KAFKA_BOOTSTRAP_SERVERS" .env
```

### Step 2: Deploy Consumer Application

```bash
./deploy-consumer.sh
```

This deploys:
- **Consumer Deployment**: Kubernetes deployment running the transaction processor
  - Registers as consumer group `trade-tx-consumer` with MSK
  - Polls messages from topic `trade-tx`
  - Uses **microbatching** to aggregate records before processing (configurable `BATCH_SIZE`)
  - Simulates batch DB writes by waiting `BATCH_PROCESSING_TIME` for each batch
  - Implements **Kafka cooperative rebalancing** to minimize processing interruption during scale events

- **KEDA ScaledObject**: Configures autoscaling behavior
  - Monitors `OffsetLag` metric (pending messages per partition)
  - Scales from **0 to 100 replicas** based on lag threshold (configurable `LAG_THRESHOLD = 10000`)
  - When lag > 10000: KEDA scales up pods to meet demand
  - When lag < 10000: KEDA scales down to reduce costs
  - When lag = 0: KEDA scales to zero after cooldown period

**Microbatching benefits**: Aggregating multiple records into a single DB operation significantly reduces write latency—the typical bottleneck in transaction processing.

### Step 3: Deploy Producer (Low Load)

Deploy the producer with initial low load:

```bash
./deploy-producer.sh 10
```

This creates a Kubernetes deployment generating simulated trade transactions at **~10 messages/second**. In production, this would be replaced by an ingress layer managing client connections.

**Check producer logs:**
```bash
kubectl wait --for=condition=ready pod -l app=trade-tx-producer --timeout=60s
sleep 5
kubectl logs -l app=trade-tx-producer
```

Expected output:
```
pod/trade-tx-producer-85f45bfd5f-8kcxd condition met
[2025-12-30 16:12:06] INFO: Creating producer with bootstrap_servers: b-1.mskdemocluster.33uj55.c5.kafka.us-east-1.amazonaws.com:9098,b-2.mskdemocluster.33uj55.c5.kafka.us-east-1.amazonaws.com:9098
[2025-12-30 16:12:06] INFO: Starting continuous producer: 10 messages/second
[2025-12-30 16:12:06] INFO: Target interval: 0.100000 seconds
[2025-12-30 16:12:11] INFO: Sent: 51 messages, Rate: 10.2 msg/s, Target: 10 msg/s
```

**Check consumer logs:**
```bash
kubectl wait --for=condition=ready pod -l app=trade-tx-consumer --timeout=60s
kubectl logs -l app=trade-tx-consumer
```

Expected output:
```
pod/trade-tx-consumer-bdb4ff757-gh2bd condition met
[2025-12-30 16:12:21] INFO: Batch size: 100, Batch timeout: 0.1s
[2025-12-30 16:12:21] INFO: Metrics available at :8000/metrics
[2025-12-30 16:12:25] INFO: Processing batch of 1 messages
[2025-12-30 16:12:26] INFO: Processing batch of 100 messages
```

**Monitor HPA autoscaling:**
```bash
kubectl get hpa
```

At 10 msg/s, lag stays below the 1000-message threshold, so only **1 replica** runs:
```
NAME                                REFERENCE                      TARGETS       MINPODS   MAXPODS   REPLICAS   AGE
keda-hpa-trade-tx-consumer-scaler   Deployment/trade-tx-consumer   14/10k (avg)   1         100       1          32m
```

### Step 4: Simulate Demand Spike

Increase load to simulate a market event:

```bash
./deploy-producer.sh 1000
```

This increases message generation to **~1000 messages/second** (100x spike).

**Monitor HPA autoscaling:**
```bash
kubectl get hpa
```

Increase load again to **~5000 messages/second** (5x spike).:

```bash
./deploy-producer.sh 5000
```

HPA scales up to meet demand after waiting for the configured stabilization windows and timing delays that smooth out scaling events.

### Step 5: Scale to Zero

Stop the producer to simulate zero load:

```bash
kubectl delete deployment -n default trade-tx-producer
```

Once the consumer pods process all remaining messages and lag reaches zero, KEDA waits for the cooldown period, then:
1. Deletes the HPA
2. Scales the deployment to **0 replicas**

This eliminates compute costs during idle periods while maintaining instant readiness to scale back up when new messages arrive.

## Monitoring

**Access Grafana dashboard:**
```bash
kubectl port-forward -n kube-system svc/kube-prometheus-stack-grafana 3000:80
```
Open http://localhost:3000 (default credentials: admin/prom-operator)

**Access provided dashboard:**
Title: "MSK & KEDA Monitoring"

![Grafana Dashboard](images/Grafana-Dash.png)

The chart shows how the system autoscales during a traffic spike from 1k msg/s to 5k msg/s

## Clean Up

```bash
cd infra-tf
terraform destroy
```

## Configuration

Edit `.env` files in application directories:

**Producer (`trade-tx-producer/.env`):**
- `MESSAGES_PER_SECOND`: Message generation rate

**Consumer (`trade-tx-consumer/.env`):**
- `BATCH_SIZE`: Messages per microbatch
- `BATCH_PROCESSING_TIME`: Simulated DB write time in seconds

## Project Structure

```
.
├── deploy-infra.sh           # Deploy infrastructure
├── deploy-producer.sh        # Deploy producer
├── deploy-consumer.sh        # Deploy consumer
├── infra-tf/                 # Terraform configuration
├── trade-tx-producer/        # Producer application
└── trade-tx-consumer/        # Consumer application
```
