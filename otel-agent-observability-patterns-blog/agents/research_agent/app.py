"""FastAPI application for the research agent with OTEL instrumentation."""

import os
import logging
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

# --- OTEL Initialization (Strands SDK built-in) ---
# Mode 1: Direct to Langfuse (LANGFUSE_BASE_URL set)
# Mode 2: Via OTEL Collector or ADOT (OTEL_EXPORTER_OTLP_ENDPOINT set)
if os.getenv("LANGFUSE_BASE_URL"):
    try:
        import base64
        from strands.telemetry import StrandsTelemetry

        auth_str = f"{os.getenv('LANGFUSE_PUBLIC_KEY', '')}:{os.getenv('LANGFUSE_SECRET_KEY', '')}"
        auth_bytes = base64.b64encode(auth_str.encode()).decode()

        os.environ["OTEL_EXPORTER_OTLP_ENDPOINT"] = os.getenv("LANGFUSE_BASE_URL") + "/api/public/otel"
        os.environ["OTEL_EXPORTER_OTLP_HEADERS"] = f"Authorization=Basic {auth_bytes},x-langfuse-ingestion-version=4"

        StrandsTelemetry().setup_otlp_exporter()
    except ImportError:
        pass
elif os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT"):
    try:
        from strands.telemetry import StrandsTelemetry
        StrandsTelemetry().setup_otlp_exporter()
    except ImportError:
        pass

# Instrument httpx for W3C traceparent propagation through Bifrost
try:
    from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
    HTTPXClientInstrumentor().instrument()
except ImportError:
    pass

from strands import Agent
from strands.models.openai import OpenAIModel
from agents.research_agent.tools.web_search import web_search
from agents.research_agent.tools.summarize import summarize

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Agent setup ---
# Route through Bifrost (OpenAI-compatible LLM gateway).
# Bifrost handles model routing to Bedrock, fallback, and cost tracking.
BIFROST_ENDPOINT = os.getenv("BIFROST_ENDPOINT", "http://bifrost.agents:8080")
# Use provider-prefixed model ID so Bifrost can auto-resolve the provider
MODEL_ALIAS = os.getenv("BIFROST_MODEL_ALIAS", "bedrock/us.anthropic.claude-sonnet-4-6")

model = OpenAIModel(
    client_args={
        "base_url": f"{BIFROST_ENDPOINT}/v1",
        "api_key": "bifrost-internal",  # Bifrost doesn't require real API keys for internal traffic
    },
    model_id=MODEL_ALIAS,
)

agent = Agent(
    model=model,
    system_prompt=(
        "You are a financial research agent specializing in market analysis. "
        "Use the web_search tool to find current market data and the summarize "
        "tool to condense long findings into actionable insights."
    ),
    tools=[web_search, summarize],
)

# --- FastAPI app ---
app = FastAPI(title="Research Agent", version="1.0.0")


class InvokeRequest(BaseModel):
    query: str


class InvokeResponse(BaseModel):
    response: str
    tokens_input: int = 0
    tokens_output: int = 0


@app.get("/health")
def health():
    return {"status": "healthy", "agent": "research-agent"}


@app.post("/invoke", response_model=InvokeResponse)
def invoke(request: InvokeRequest):
    """Invoke the research agent with a user query."""
    try:
        result = agent(request.query)

        tokens_in = getattr(result, "usage", None)
        input_tokens = tokens_in.input_tokens if tokens_in else 0
        output_tokens = tokens_in.output_tokens if tokens_in else 0

        return InvokeResponse(
            response=str(result),
            tokens_input=input_tokens,
            tokens_output=output_tokens,
        )
    except Exception as e:
        logger.error(f"Agent invocation failed: {e}")
        raise HTTPException(status_code=500, detail=str(e))
