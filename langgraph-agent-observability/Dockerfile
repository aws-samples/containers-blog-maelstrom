FROM python:3.11-slim

WORKDIR /app

# Set environment variables
ENV AWS_REGION=us-west-2
ENV AWS_DEFAULT_REGION=us-west-2

# Bedrock Configuration
ENV BEDROCK_MODEL_ID=us.anthropic.claude-sonnet-4-20250514-v1:0

# OpenTelemetry Configuration
ENV OTEL_PYTHON_DISTRO=aws_distro
ENV OTEL_PYTHON_CONFIGURATOR=aws_configurator
ENV OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
ENV OTEL_TRACES_EXPORTER=otlp
ENV OTEL_METRICS_EXPORTER=otlp
ENV OTEL_LOGS_EXPORTER=otlp
ENV OTEL_EXPORTER_OTLP_ENDPOINT=https://cloudwatch-cross-region.amazonaws.com
ENV OTEL_EXPORTER_OTLP_HEADERS=x-aws-service=cloudwatch
ENV OTEL_RESOURCE_ATTRIBUTES=service.name=langgraph-travel-agent,service.version=1.0.0,aws.bedrock.agent.name=langgraph-travel-agent,aws.bedrock.agent.version=1.0
ENV OTEL_EXPORTER_OTLP_LOGS_HEADERS=x-aws-log-group=langgraph-agent-logs,x-aws-log-stream=default
ENV OTEL_EXPORTER_OTLP_METRICS_HEADERS=x-aws-metric-namespace=AWS/Bedrock/AgentCore
ENV AGENT_OBSERVABILITY_ENABLED=true

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py main.py

CMD ["tail", "-f", "/dev/null"]