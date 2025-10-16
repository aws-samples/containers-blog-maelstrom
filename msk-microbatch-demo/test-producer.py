#!/usr/bin/env python3

from kafka import KafkaProducer
import json
import time
import sys

# Configuration
BOOTSTRAP_SERVERS = "b-1.mskdemocluster.z9izqk.c4.kafka.us-west-2.amazonaws.com:9096,b-3.mskdemocluster.z9izqk.c4.kafka.us-west-2.amazonaws.com:9096,b-2.mskdemocluster.z9izqk.c4.kafka.us-west-2.amazonaws.com:9096"
TOPIC = "microbatch-topic"
USERNAME = os.getenv("KAFKA_USERNAME", "your-kafka-username")
PASSWORD = os.getenv("KAFKA_PASSWORD", "your-kafka-password")

def create_producer():
    return KafkaProducer(
        bootstrap_servers=BOOTSTRAP_SERVERS,
        security_protocol='SASL_SSL',
        sasl_mechanism='SCRAM-SHA-512',
        sasl_plain_username=USERNAME,
        sasl_plain_password=PASSWORD,
        value_serializer=lambda v: json.dumps(v).encode('utf-8')
    )

def send_messages(count=50):
    producer = create_producer()
    
    for i in range(count):
        message = {
            "id": i,
            "timestamp": time.time(),
            "data": f"Test message {i}",
            "batch_id": i // 10
        }
        
        producer.send(TOPIC, message)
        print(f"Sent message {i}")
        time.sleep(0.1)
    
    producer.flush()
    producer.close()
    print(f"Sent {count} messages to topic {TOPIC}")

if __name__ == "__main__":
    count = int(sys.argv[1]) if len(sys.argv) > 1 else 50
    send_messages(count)
