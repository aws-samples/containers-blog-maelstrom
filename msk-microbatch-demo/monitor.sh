#!/bin/bash

echo "MSK Microbatch Demo Monitoring"
echo "=============================="

while true; do
    clear
    echo "MSK Microbatch Demo Monitoring - $(date)"
    echo "=============================="
    
    echo -e "\n📦 Pods Status:"
    kubectl get pods -n msk-microbatch-demo -o wide
    
    echo -e "\n🔧 HPA Status:"
    kubectl get hpa kafka-processor-hpa -n msk-microbatch-demo
    
    echo -e "\n📊 Resource Usage:"
    kubectl top pods -n msk-microbatch-demo 2>/dev/null || echo "Metrics not available"
    
    echo -e "\n📝 Recent Logs (last 10 lines):"
    kubectl logs -n msk-microbatch-demo deployment/kafka-batch-processor --tail=10 2>/dev/null || echo "No logs available"
    
    echo -e "\n⏱️  Refreshing in 10 seconds... (Ctrl+C to exit)"
    sleep 10
done
