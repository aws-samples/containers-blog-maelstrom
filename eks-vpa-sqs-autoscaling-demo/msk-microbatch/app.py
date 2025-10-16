from kafka import KafkaConsumer
import os
import json
import logging
import time

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

class KafkaBatchProcessor:
    def __init__(self):
        self.bootstrap_servers = os.environ['BOOTSTRAP_SERVERS']
        self.topic = os.environ['KAFKA_TOPIC']
        self.group_id = os.environ['CONSUMER_GROUP']
        self.batch_size = int(os.environ.get('BATCH_SIZE', '10'))
        self.process_time = int(os.environ.get('PROCESS_TIME_SECONDS', '2'))
        
        self.consumer = KafkaConsumer(
            self.topic,
            bootstrap_servers=self.bootstrap_servers,
            group_id=self.group_id,
            security_protocol='SASL_SSL',
            sasl_mechanism='SCRAM-SHA-512',
            sasl_plain_username=os.environ['KAFKA_USERNAME'],
            sasl_plain_password=os.environ['KAFKA_PASSWORD'],
            auto_offset_reset='earliest',
            enable_auto_commit=False
        )

    def process_batch(self, messages):
        try:
            logger.info(f"Processing batch of {len(messages)} messages")
            
            for message in messages:
                logger.info(f"Processing message from partition {message.partition}, offset {message.offset}")
                time.sleep(self.process_time)
                
            self.consumer.commit()
            logger.info("Successfully committed offsets")
            
        except Exception as e:
            logger.error(f"Error processing batch: {e}")
            raise

    def run(self):
        logger.info(f"Starting Kafka batch processor for topic: {self.topic}")
        messages = []
        
        try:
            for message in self.consumer:
                messages.append(message)
                
                if len(messages) >= self.batch_size:
                    self.process_batch(messages)
                    messages = []
                    
        except Exception as e:
            logger.error(f"Error in processing loop: {e}")
        finally:
            self.consumer.close()

if __name__ == "__main__":
    processor = KafkaBatchProcessor()
    processor.run()
