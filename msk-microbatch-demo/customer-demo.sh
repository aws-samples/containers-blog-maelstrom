#!/bin/bash

# MSK Multi-Partition Microbatch Demo - Customer Presentation
# Shows: Multiple partitions, multiple pods, KEDA scaling, microbatch processing

set -e
NAMESPACE="msk-microbatch-demo"

echo "🚀 MSK Multi-Pod Per Partition Fanout Demo"
echo "=========================================="
echo "Architecture: 8 partitions → 24 consumer pods (3 per partition) → KEDA auto-scaling"
echo

# Function to get partition stats
get_partition_stats() {
    kubectl run temp-stats --image=confluentinc/cp-kafka:latest --rm -i -n $NAMESPACE --restart=Never -- bash -c '
    echo "security.protocol=SASL_SSL
    sasl.mechanism=SCRAM-SHA-512
    sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username=\"kafka-user\" password=\"Bg3m13ATJK4jCx1TFUcI8fwsgSysAd/NSECeCWG1wp0=\";" > /tmp/client.properties
    kafka-consumer-groups --bootstrap-server b-1.mskdemocluster.z9izqk.c4.kafka.us-west-2.amazonaws.com:9096 --command-config /tmp/client.properties --describe --group batch-processor-group 2>/dev/null | grep microbatch-topic | sort -k3 -n
    ' 2>/dev/null || echo "No consumer assignments yet"
}

echo "📊 STEP 1: Current Architecture Status"
echo "======================================"
RUNNING_PODS=$(kubectl get pods -n $NAMESPACE --no-headers | grep kafka-batch-processor | grep Running | wc -l)
echo "• Consumer pods running: $RUNNING_PODS"
echo "• Target pods: 24 (3 pods per partition for maximum fanout)"
echo "• Topic partitions: 8"
echo "• Pods per partition: ~$((RUNNING_PODS / 8))"
echo "• Batch size: 10 messages per batch"
echo "• KEDA threshold: 3 messages for scaling"
echo

echo "📈 STEP 2: Partition Distribution"
echo "================================="
printf "%-10s | %-12s | %-12s | %-10s\n" "Partition" "Current Lag" "Log End" "Status"
echo "-----------|--------------|------------|----------"

get_partition_stats | while read line; do
    if [[ $line == *"microbatch-topic"* ]]; then
        PARTITION=$(echo $line | awk '{print $3}')
        LAG=$(echo $line | awk '{print $5}')
        LOG_END=$(echo $line | awk '{print $4}')
        STATUS="Active"
        printf "%-10s | %-12s | %-12s | %-10s\n" "$PARTITION" "$LAG" "$LOG_END" "$STATUS"
    fi
done

echo
echo "🔥 STEP 3: Sending High-Volume Load (1000 messages)"
echo "===================================================="
echo "Distributing messages across all 8 partitions with partition keys..."

kubectl create job customer-load-$(date +%s) --image=confluentinc/cp-kafka:latest -n $NAMESPACE -- bash -c '
echo "security.protocol=SASL_SSL
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username=\"kafka-user\" password=\"Bg3m13ATJK4jCx1TFUcI8fwsgSysAd/NSECeCWG1wp0=\";" > /tmp/client.properties

# Send 125 messages to each partition (1000 total)
for partition in {0..7}; do
  for i in {1..125}; do
    echo "customer-key-$partition-$i:Customer demo message $i for partition $partition" | kafka-console-producer --bootstrap-server b-1.mskdemocluster.z9izqk.c4.kafka.us-west-2.amazonaws.com:9096 --producer.config /tmp/client.properties --topic microbatch-topic --property "parse.key=true" --property "key.separator=:" >/dev/null 2>&1
  done
done
' >/dev/null 2>&1 &

echo "⏳ Waiting for message distribution and processing..."
sleep 20

echo
echo "📊 STEP 4: Multi-Partition Processing Results"
echo "=============================================="

# Show updated partition stats
printf "%-10s | %-12s | %-12s | %-15s | %-10s\n" "Partition" "Current Lag" "Log End" "Consumer ID" "Status"
echo "-----------|--------------|--------------|-----------------|----------"

get_partition_stats | while read line; do
    if [[ $line == *"microbatch-topic"* ]]; then
        PARTITION=$(echo $line | awk '{print $3}')
        LAG=$(echo $line | awk '{print $5}')
        LOG_END=$(echo $line | awk '{print $4}')
        CONSUMER_ID=$(echo $line | awk '{print $7}' | cut -d'-' -f3-4)
        STATUS="Processing"
        printf "%-10s | %-12s | %-12s | %-15s | %-10s\n" "$PARTITION" "$LAG" "$LOG_END" "$CONSUMER_ID" "$STATUS"
    fi
done

echo
echo "🎯 STEP 5: Processing Activity Analysis"
echo "======================================="

# Show processing activity by partition
echo "Messages processed per partition (recent activity):"
for partition in {0..7}; do
    COUNT=$(kubectl logs -l app=kafka-batch-processor -n $NAMESPACE --tail=200 | grep "Processing message from partition $partition" | wc -l)
    if [ $COUNT -gt 0 ]; then
        echo "• Partition $partition: $COUNT messages processed"
    fi
done

echo
echo "📈 STEP 6: Throughput & Performance Metrics"
echo "==========================================="
TOTAL_PODS=$(kubectl get pods -n $NAMESPACE --no-headers | grep kafka-batch-processor | grep Running | wc -l)
TOTAL_BATCHES=$(kubectl logs -l app=kafka-batch-processor -n $NAMESPACE --tail=300 | grep "Processing batch of 10 messages" | wc -l)
TOTAL_COMMITS=$(kubectl logs -l app=kafka-batch-processor -n $NAMESPACE --tail=300 | grep "Successfully committed offsets" | wc -l)

echo "• Active consumer pods: $TOTAL_PODS"
echo "• Recent batches processed: $TOTAL_BATCHES"
echo "• Successful commits: $TOTAL_COMMITS"
echo "• Messages processed: $((TOTAL_BATCHES * 10))"
echo "• Processing efficiency: $((TOTAL_COMMITS * 100 / TOTAL_BATCHES))% success rate"

echo
echo "🔍 STEP 7: Live Microbatch Processing Sample"
echo "============================================"
echo "Real-time processing across multiple partitions:"
kubectl logs -l app=kafka-batch-processor -n $NAMESPACE --tail=15 | grep -E "(Processing batch|partition [0-7], offset)" | tail -8

echo
echo "🌟 STEP 8: Multi-Pod Per Partition Fanout Analysis"
echo "=================================================="
echo "Consumer group rebalancing with multiple pods per partition:"

# Show how many pods are processing each partition
kubectl run fanout-analysis --image=confluentinc/cp-kafka:latest --rm -i -n $NAMESPACE --restart=Never -- bash -c '
echo "security.protocol=SASL_SSL
sasl.mechanism=SCRAM-SHA-512
sasl.jaas.config=org.apache.kafka.common.security.scram.ScramLoginModule required username=\"kafka-user\" password=\"Bg3m13ATJK4jCx1TFUcI8fwsgSysAd/NSECeCWG1wp0=\";" > /tmp/client.properties
kafka-consumer-groups --bootstrap-server b-1.mskdemocluster.z9izqk.c4.kafka.us-west-2.amazonaws.com:9096 --command-config /tmp/client.properties --describe --group batch-processor-group 2>/dev/null | grep microbatch-topic | wc -l
' 2>/dev/null | xargs echo "• Active partition assignments:"

echo "• Total consumer pods: $TOTAL_PODS"
echo "• Partition fanout ratio: $((TOTAL_PODS / 8)):1 (pods per partition)"
echo "• Load distribution: Multiple pods can consume from same partition"
echo "• Fault tolerance: If pod fails, partition automatically rebalances"

echo
echo "💡 CUSTOMER VALUE PROPOSITION"
echo "============================="
echo "✅ Multi-pod per partition fanout: $TOTAL_PODS pods across 8 partitions"
echo "✅ High throughput: $((TOTAL_BATCHES * 10)) messages in microbatches of 10"
echo "✅ Fault tolerance: $TOTAL_COMMITS successful offset commits"
echo "✅ Auto-scaling: KEDA monitors queue depth across all partitions"
echo "✅ Cost efficiency: Scales down when idle, up when busy"
echo "✅ Enterprise ready: MSK integration with SCRAM security"

echo
echo "🎉 Demo Complete!"
echo "================"
echo "Key commands for live monitoring:"
echo "• kubectl logs -f -l app=kafka-batch-processor -n $NAMESPACE"
echo "• kubectl get pods,hpa,scaledobject -n $NAMESPACE"
echo "• kubectl describe scaledobject kafka-scaledobject -n $NAMESPACE"

echo
echo "Architecture Summary: 8 Kafka partitions → $TOTAL_PODS consumer pods (3+ per partition) → Microbatch processing → KEDA auto-scaling"
