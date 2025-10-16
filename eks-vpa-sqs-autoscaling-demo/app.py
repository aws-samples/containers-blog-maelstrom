import boto3
import os
import time
import json
from concurrent.futures import ThreadPoolExecutor

sqs = boto3.client('sqs')
queue_url = os.environ['QUEUE_URL']

def process_message(message):
    """Simulate CPU and memory intensive processing"""
    print(f"Processing message: {message['Body']}")
    
    # Simulate CPU intensive work
    result = 0
    for i in range(1000000):
        result += i * i
    
    # Simulate memory usage
    data = [i for i in range(100000)]
    
    # Simulate processing time
    time.sleep(2)
    
    # Delete the message
    sqs.delete_message(
        QueueUrl=queue_url,
        ReceiptHandle=message['ReceiptHandle']
    )
    print(f"Completed processing message: {message['MessageId']}")

def main():
    print(f"Starting SQS consumer for queue: {queue_url}")
    
    with ThreadPoolExecutor(max_workers=4) as executor:
        while True:
            try:
                response = sqs.receive_message(
                    QueueUrl=queue_url,
                    MaxNumberOfMessages=10,
                    WaitTimeSeconds=20
                )
                
                messages = response.get('Messages', [])
                
                if messages:
                    print(f"Received {len(messages)} messages")
                    for message in messages:
                        executor.submit(process_message, message)
                else:
                    print("No messages received, waiting...")
                    
            except Exception as e:
                print(f"Error: {e}")
                time.sleep(5)

if __name__ == "__main__":
    main()
