FROM python:3.12-slim

WORKDIR /app

COPY image-build/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy all agent code
COPY agents/ ./agents/

ARG AGENT_MODULE=research_agent
ENV AGENT_MODULE=${AGENT_MODULE}

ENV PYTHONPATH=/app
ENV OTEL_COLLECTOR_ENDPOINT=http://otel-collector.observability:4317
ENV ADOT_ENDPOINT=http://localhost:4317
ENV BIFROST_ENDPOINT=http://bifrost.agents:8080
ENV BIFROST_MODEL_ALIAS=bedrock/us.anthropic.claude-sonnet-4-6-20260514
ENV BEDROCK_PRIMARY_MODEL=us.anthropic.claude-sonnet-4-6-20260514

EXPOSE 8080

CMD ["sh", "-c", "uvicorn agents.${AGENT_MODULE}.app:app --host 0.0.0.0 --port 8080"]
