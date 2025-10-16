#!/bin/bash

# Test VPA and KEDA Scaling
set -e

GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${GREEN}=== Testing VPA and KEDA Scaling ===${NC}"

# Get queue URL
QUEUE_URL=$(aws sqs get-queue-url --queue-name vpa-demo-queue --query QueueUrl --output text)
REGION=$(aws configure get region || echo "us-west-2")

echo -e "${GREEN}Queue URL: ${QUEUE_URL}${NC}"

# Function to send messages
send_messages() {
    local count=$1
    echo -e "${YELLOW}Sending ${count} messages to SQS queue...${NC}"
    for i in $(seq 1 $count); do
        aws sqs send-message \
            --queue-url $QUEUE_URL \
            --message-body "Test message $i - $(date)" \
            --region $REGION >/dev/null
    done
    echo -e "${GREEN}Sent ${count} messages${NC}"
}

# Function to monitor resources
monitor_resources() {
    echo -e "\n${GREEN}=== Current Resource Status ===${NC}"
    
    # Pod count
    POD_COUNT=$(kubectl get pods -n vpa-sqs-scaling-demo -l app=sqs-consumer --no-headers | wc -l)
    echo -e "${YELLOW}Current pod count: ${POD_COUNT}${NC}"
    
    # VPA recommendations
    echo -e "\n${YELLOW}VPA Recommendations:${NC}"
    kubectl get vpa sqs-consumer-vpa -n vpa-sqs-scaling-demo -o jsonpath='{.status.recommendation.containerRecommendations[0]}' | jq '.' 2>/dev/null || echo "No recommendations yet"
    
    # Current resource usage
    echo -e "\n${YELLOW}Current Pod Resources:${NC}"
    kubectl get pods -n vpa-sqs-scaling-demo -l app=sqs-consumer -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.spec.containers[0].resources}{"\n"}{end}' | column -t
    
    # Queue depth
    QUEUE_DEPTH=$(aws sqs get-queue-attributes --queue-url $QUEUE_URL --attribute-names ApproximateNumberOfMessages --region $REGION --query 'Attributes.ApproximateNumberOfMessages' --output text)
    echo -e "\n${YELLOW}Queue depth: ${QUEUE_DEPTH}${NC}"
    
    # HPA status
    echo -e "\n${YELLOW}HPA Status:${NC}"
    kubectl get hpa -n vpa-sqs-scaling-demo 2>/dev/null || echo "No HPA found yet"
}

# Initial status
monitor_resources

# Test 1: Send moderate load to trigger VPA recommendations
echo -e "\n${GREEN}=== Test 1: Moderate Load (VPA Recommendations) ===${NC}"
send_messages 10
echo -e "${YELLOW}Waiting 2 minutes for VPA to analyze resource usage...${NC}"
sleep 120
monitor_resources

# Test 2: Send high load to trigger horizontal scaling
echo -e "\n${GREEN}=== Test 2: High Load (Horizontal Scaling) ===${NC}"
send_messages 50
echo -e "${YELLOW}Waiting 3 minutes for KEDA to scale horizontally...${NC}"
sleep 180
monitor_resources

# Test 3: Monitor VPA adjustments on new pods
echo -e "\n${GREEN}=== Test 3: VPA Adjustments on Scaled Pods ===${NC}"
echo -e "${YELLOW}Waiting 5 minutes for VPA to adjust resources on new pods...${NC}"
sleep 300
monitor_resources

# Test 4: Scale down test
echo -e "\n${GREEN}=== Test 4: Scale Down Test ===${NC}"
echo -e "${YELLOW}Purging queue to trigger scale down...${NC}"
aws sqs purge-queue --queue-url $QUEUE_URL --region $REGION
echo -e "${YELLOW}Waiting 5 minutes for scale down...${NC}"
sleep 300
monitor_resources

echo -e "\n${GREEN}=== Scaling Test Completed ===${NC}"
echo -e "${YELLOW}Key observations:${NC}"
echo -e "1. VPA provides resource recommendations based on actual usage"
echo -e "2. KEDA scales pods horizontally based on SQS queue depth"
echo -e "3. VPA adjusts resources on new pods created by KEDA"
echo -e "4. Both systems work together for optimal resource utilization"
