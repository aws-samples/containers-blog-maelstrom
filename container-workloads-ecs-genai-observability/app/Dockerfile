FROM python:3.11-slim

WORKDIR /app

# Build arguments
ARG BEDROCK_MODEL_ID=anthropic.claude-3-sonnet-20240229-v1:0
ARG AWS_REGION=us-west-2

# Set environment variables
ENV AWS_REGION=${AWS_REGION}
ENV AWS_DEFAULT_REGION=${AWS_REGION}
ENV BEDROCK_MODEL_ID=${BEDROCK_MODEL_ID}

# OpenTelemetry Configuration
ENV OTEL_PYTHON_DISTRO=aws_distro
ENV OTEL_PYTHON_CONFIGURATOR=aws_configurator
ENV OTEL_EXPORTER_OTLP_PROTOCOL=http/protobuf
ENV OTEL_TRACES_EXPORTER=otlp
ENV OTEL_EXPORTER_OTLP_LOGS_HEADERS=x-aws-log-group=strands-agent-logs-ecs,x-aws-log-stream=default,x-aws-metric-namespace=agents
ENV OTEL_RESOURCE_ATTRIBUTES=service.name=strands-agent-app,aws.log.group.names=strands-agent-logs-ecs
ENV AGENT_OBSERVABILITY_ENABLED=true

COPY requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

COPY main.py main.py

CMD ["opentelemetry-instrument", "python", "main.py"]