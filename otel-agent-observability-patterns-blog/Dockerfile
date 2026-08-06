FROM python:3.12-slim

WORKDIR /app

COPY image-build/requirements.txt .
RUN pip install --no-cache-dir -r requirements.txt

# Copy all agent code (shared + individual agents)
COPY agents/ ./agents/

ARG AGENT_MODULE=research_agent
ENV AGENT_MODULE=${AGENT_MODULE}

# PYTHONPATH=/app ensures `from agents.shared.otel_bootstrap import init_telemetry` resolves
ENV PYTHONPATH=/app

# Defaults — overridden by K8s deployment env vars at runtime
ENV BIFROST_ENDPOINT=http://bifrost.agents:8080
ENV BIFROST_MODEL_ALIAS=bedrock/us.anthropic.claude-sonnet-5

EXPOSE 8080

CMD ["sh", "-c", "uvicorn agents.${AGENT_MODULE}.app:app --host 0.0.0.0 --port 8080"]
