#!/usr/bin/env python3

import logging
import sys
import json
import time
import os

logging.basicConfig(
    level=logging.INFO,
    format='[%(asctime)s] %(levelname)s: %(message)s',
    datefmt='%Y-%m-%d %H:%M:%S'
)
logger = logging.getLogger(__name__)

logger.info(f"Python version: {sys.version}")

from confluent_kafka import Consumer, KafkaError, KafkaException
from aws_msk_iam_sasl_signer import MSKAuthTokenProvider
from prometheus_client import Counter, Gauge, Histogram, start_http_server

logger.info(f"confluent-kafka version: {__import__('confluent_kafka').__version__}")

# Configuration
KAFKA_BOOTSTRAP_SERVERS = os.environ['KAFKA_BOOTSTRAP_SERVERS']
REGION = os.environ.get('AWS_REGION', 'us-east-1')
KAFKA_TOPIC = os.environ['KAFKA_TOPIC']
CONSUMER_GROUP = os.environ['CONSUMER_GROUP']
BATCH_SIZE = int(os.environ.get('BATCH_SIZE', '10'))
BATCH_TIMEOUT_SECONDS = float(os.environ.get('BATCH_TIMEOUT_SECONDS', '0.01'))
BATCH_PROCESSING_TIME = float(os.environ.get('BATCH_PROCESSING_TIME', '1'))
MESSAGE_PROCESSING_TIME = float(os.environ.get('MESSAGE_PROCESSING_TIME', '0.0001'))

# Prometheus metrics
messages_processed = Counter('kafka_messages_processed_total', 'Total messages processed', ['status'])
messages_per_second = Gauge('kafka_messages_per_second', 'Current message processing rate')
batch_processing_time = Histogram('kafka_batch_processing_seconds', 'Time to process a batch')
message_age = Histogram('kafka_message_age_seconds', 'Time from message production to consumption')

def oauth_cb(oauth_config):
    """OAuth callback for MSK IAM authentication"""
    token, _ = MSKAuthTokenProvider.generate_auth_token(REGION)
    return token, time.time() + 300

class KafkaBatchProcessor:
    def __init__(self):
        self.bootstrap_servers = KAFKA_BOOTSTRAP_SERVERS
        self.topic = KAFKA_TOPIC
        self.group_id = CONSUMER_GROUP
        self.batch_size = BATCH_SIZE
        self.batch_timeout = BATCH_TIMEOUT_SECONDS
        self.batch_process_time = BATCH_PROCESSING_TIME
        self.message_process_time = MESSAGE_PROCESSING_TIME
        
        logger.info(f"Creating consumer with bootstrap_servers: {self.bootstrap_servers}")
        
        conf = {
            'bootstrap.servers': self.bootstrap_servers,
            'group.id': self.group_id,
            'auto.offset.reset': 'latest',
            'enable.auto.commit': False,
            'partition.assignment.strategy': 'cooperative-sticky',
            'security.protocol': 'SASL_SSL',
            'sasl.mechanism': 'OAUTHBEARER',
            'oauth_cb': oauth_cb,
            'session.timeout.ms': 10000,  # Faster group coordination
            'heartbeat.interval.ms': 1000,  # More frequent heartbeats
            'max.poll.interval.ms': 300000,
            'fetch.min.bytes': 1,  # Don't wait for large batches
            'fetch.wait.max.ms': 10,  # Very short wait
            'max.partition.fetch.bytes': 131072,  # 128KB per partition
            'connections.max.idle.ms': 540000,  # Keep connections alive
            'reconnect.backoff.ms': 50  # Fast reconnection
        }
        
        self.consumer = Consumer(conf)
        self.consumer.subscribe([self.topic])
        
        self.total_messages = 0
        self.start_time = time.time()

    def process_batch(self, messages):
        try:
            with batch_processing_time.time():
                logger.info(f"Processing batch of {len(messages)} messages")
                
                for msg in messages:
                    value = json.loads(msg.value().decode('utf-8'))
                    
                    # Calculate message age
                    if msg.timestamp()[1]:
                        age = (time.time() * 1000 - msg.timestamp()[1]) / 1000
                        message_age.observe(age)
                    
                    time.sleep(self.message_process_time)
                    messages_processed.labels(status='success').inc()
                    self.total_messages += 1
                
                # Batch processing time
                time.sleep(self.batch_process_time)
                
                # Commit offsets only if we have messages
                if messages:
                    try:
                        self.consumer.commit(asynchronous=False)
                        # logger.info("Successfully committed offsets")
                    except KafkaException as e:
                        error_code = e.args[0].code()
                        if error_code in (KafkaError.ILLEGAL_GENERATION, KafkaError._ASSIGNMENT_LOST, KafkaError._NO_OFFSET):
                            logger.warning(f"Commit failed ({error_code}), messages will be reprocessed")
                        else:
                            raise
                
                # Update rate metric
                elapsed = time.time() - self.start_time
                if elapsed > 0:
                    rate = self.total_messages / elapsed
                    messages_per_second.set(rate)
                
        except Exception as e:
            logger.error(f"Error processing batch: {e}")
            messages_processed.labels(status='error').inc()
            raise

    def run(self):
        logger.info(f"Starting Kafka batch processor for topic: {self.topic}")
        logger.info(f"Batch size: {self.batch_size}, Batch timeout: {self.batch_timeout}s")
        logger.info("Metrics available at :8000/metrics")
        messages = []
        batch_start_time = time.time()
        
        try:
            while True:
                msg = self.consumer.poll(timeout=1.0)  # Longer poll timeout
                
                if msg is not None and not msg.error():
                    messages.append(msg)
                elif msg is not None and msg.error():
                    if msg.error().code() != KafkaError._PARTITION_EOF:
                        raise KafkaException(msg.error())
                
                # Process batch if full OR timeout reached
                batch_elapsed = time.time() - batch_start_time
                if len(messages) >= self.batch_size or (messages and batch_elapsed >= self.batch_timeout):
                    self.process_batch(messages)
                    messages = []
                    batch_start_time = time.time()
                    
        except KeyboardInterrupt:
            logger.info("Shutting down...")
        finally:
            self.consumer.close()

if __name__ == "__main__":
    start_http_server(8000)
    processor = KafkaBatchProcessor()
    processor.run()
