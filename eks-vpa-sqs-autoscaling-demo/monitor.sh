#!/bin/bash

# Real-time monitoring script for VPA and KEDA
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m'

echo -e "${GREEN}=== Real-time VPA and KEDA Monitor ===${NC}"
echo -e "${YELLOW}Press Ctrl+C to stop monitoring${NC}"

while true; do
    clear
    echo -e "${GREEN}=== VPA SQS Scaling Demo - Live Monitor ===${NC}"
    echo -e "$(date)"
    
    # Pod status
    echo -e "\n${YELLOW}=== Pod Status ===${NC}"
    kubectl get pods -n vpa-sqs-scaling-demo -l app=sqs-consumer -o wide
    
    # VPA status
    echo -e "\n${YELLOW}=== VPA Recommendations ===${NC}"
    kubectl describe vpa sqs-consumer-vpa -n vpa-sqs-scaling-demo | grep -A 10 "Container Recommendations" || echo "No recommendations yet"
    
    # HPA status (created by KEDA)
    echo -e "\n${YELLOW}=== HPA Status ===${NC}"
    kubectl get hpa -n vpa-sqs-scaling-demo 2>/dev/null || echo "No HPA found"
    
    # KEDA ScaledObject status
    echo -e "\n${YELLOW}=== KEDA ScaledObject Status ===${NC}"
    kubectl get scaledobject -n vpa-sqs-scaling-demo
    
    # Queue depth
    echo -e "\n${YELLOW}=== SQS Queue Status ===${NC}"
    QUEUE_URL=$(aws sqs get-queue-url --queue-name vpa-demo-queue --query QueueUrl --output text 2>/dev/null)
    if [ ! -z "$QUEUE_URL" ]; then
        QUEUE_DEPTH=$(aws sqs get-queue-attributes --queue-url $QUEUE_URL --attribute-names ApproximateNumberOfMessages --query 'Attributes.ApproximateNumberOfMessages' --output text 2>/dev/null)
        echo -e "Queue Depth: ${QUEUE_DEPTH}"
    else
        echo "Queue not found"
    fi
    
    # Resource usage
    echo -e "\n${YELLOW}=== Current Resource Requests/Limits ===${NC}"
    kubectl get pods -n vpa-sqs-scaling-demo -l app=sqs-consumer -o jsonpath='{range .items[*]}{.metadata.name}{"\n"}{.spec.containers[0].resources}{"\n\n"}{end}' 2>/dev/null
    
    sleep 10
done
