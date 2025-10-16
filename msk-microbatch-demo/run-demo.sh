#!/bin/bash

set -e

echo "🚀 MSK Microbatch Processing Demo with HPA"
echo "================================="

# Make scripts executable
chmod +x *.sh

echo "Step 1: Setting up MSK cluster..."
./setup-msk.sh

echo -e "\n⚠️  MANUAL STEP REQUIRED:"
echo "1. Get Kafka credentials from AWS Secrets Manager:"
echo "   aws secretsmanager get-secret-value --secret-id msk-demo-credentials"
echo "2. Update 03-secret.yaml with the actual credentials"
echo "3. Press Enter when ready to continue..."
read

echo -e "\nStep 2: Deploying application..."
./deploy.sh

echo -e "\nStep 3: Waiting for pods to be ready..."
kubectl wait --for=condition=ready pod -l app=kafka-batch-processor -n msk-microbatch-demo --timeout=300s

echo -e "\nStep 4: Demo is ready!"
echo "📊 Monitor with: ./monitor.sh"
echo "📤 Send test messages with: python3 test-producer.py [count]"
echo "🧹 Cleanup with: ./cleanup.sh"

echo -e "\n✅ Demo setup complete!"
echo "The Kafka batch processor is now running and HPA will scale pods based on CPU/memory usage."
