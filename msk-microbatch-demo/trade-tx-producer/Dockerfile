FROM python:3.11-slim

WORKDIR /app

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY trade-tx-producer.py .

CMD ["python", "trade-tx-producer.py"]
