#!/usr/bin/env python3

import logging
logging.basicConfig(level=logging.INFO)

from kafka import KafkaProducer
from aws_msk_iam_sasl_signer import MSKAuthTokenProvider
import json
import time
import sys
import os
import random
from datetime import datetime

# Configuration from environment variables
BOOTSTRAP_SERVERS = os.getenv("KAFKA_BOOTSTRAP_SERVERS")
REGION = os.getenv("AWS_REGION", "us-east-1")
TOPIC = os.getenv("KAFKA_TOPIC", "demo-topic")
PRODUCER_MESSAGES = int(os.getenv("PRODUCER_MESSAGES", 50))
MESSAGE_PRODUCE_TIME = float(os.getenv("MESSAGE_PRODUCE_TIME", 0.01))

class TokenProvider:
    def __init__(self, region):
        self.region = region
    
    def token(self):
        token, _ = MSKAuthTokenProvider.generate_auth_token(self.region)
        return token

def create_producer():
    print(f"Creating producer with bootstrap_servers: {BOOTSTRAP_SERVERS}")
    return KafkaProducer(
        bootstrap_servers=BOOTSTRAP_SERVERS,
        security_protocol='SASL_SSL',
        sasl_mechanism='OAUTHBEARER',
        sasl_oauth_token_provider=TokenProvider(REGION),
        value_serializer=lambda v: json.dumps(v).encode('utf-8'),
        api_version=(2, 5, 0)
    )

def generate_trade():
    account_id = f"ACC{random.randint(1000, 9999)}"
    symbols = ['AAPL', 'GOOGL', 'MSFT', 'AMZN', 'TSLA', 'META', 'NVDA']
    trade_types = ['BUY', 'SELL']
    
    return {
        "account_id": account_id,
        "trade_id": f"TRD{random.randint(100000, 999999)}",
        "symbol": random.choice(symbols),
        "trade_type": random.choice(trade_types),
        "quantity": random.randint(1, 1000),
        "price": round(random.uniform(50, 500), 2),
        "timestamp": datetime.utcnow().isoformat()
    }, account_id

def send_messages(count=50):
    producer = create_producer()
    
    for i in range(count):
        trade, account_id = generate_trade()
        time.sleep(MESSAGE_PRODUCE_TIME)
        producer.send(TOPIC, key=account_id.encode('utf-8'), value=trade)
        print(f"Sent trade {i}: {trade['trade_type']} {trade['quantity']} {trade['symbol']} for {account_id}")
    
    producer.flush()
    producer.close()
    print(f"Sent {count} trade transactions to topic {TOPIC}")

if __name__ == "__main__":
    count = int(sys.argv[1]) if len(sys.argv) > 1 else PRODUCER_MESSAGES
    send_messages(count)
