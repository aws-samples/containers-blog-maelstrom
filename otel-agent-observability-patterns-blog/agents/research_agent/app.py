"""Research agent — Strands SDK agent instrumented for both observability patterns.

Telemetry is bootstrapped once at startup by init_telemetry(). The active pattern
is determined entirely by env vars — no code changes needed when switching:

  Pattern 1 (Decentralized): set LANGFUSE_BASE_URL + keys on the pod
  Pattern 2 (Centralized):   set OTEL_EXPORTER_OTLP_ENDPOINT on the pod

All LLM calls route through Bifrost (BIFROST_ENDPOINT). Bifrost reads the
W3C traceparent header injected by HTTPXClientInstrumentor and creates a child
span under the same trace ID, producing a unified trace in Langfuse:

  agent.invoke
    ├── tool.call: web_search
    ├── [Bifrost] bedrock.invoke: claude-sonnet-5  ← cost + token attrs
    ├── tool.call: summarize
    └── [Bifrost] bedrock.invoke: claude-sonnet-5  ← cost + token attrs
"""

import os
import logging
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from agents.shared.otel_bootstrap import init_telemetry

# Bootstrap telemetry before importing Strands so the TracerProvider is
# registered before the SDK creates any spans.
init_telemetry(service_name=os.getenv("OTEL_SERVICE_NAME", "research-agent"))

from strands import Agent                                 # noqa: E402
from strands.models.openai import OpenAIModel            # noqa: E402
from agents.research_agent.tools.web_search import web_search   # noqa: E402
from agents.research_agent.tools.summarize import summarize      # noqa: E402

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Bifrost LLM gateway — shared by both patterns.
# Bifrost routes to Bedrock, handles model fallback (Sonnet → Haiku on
# throttle), and emits correlated OTEL spans to Langfuse.
# ---------------------------------------------------------------------------
BIFROST_ENDPOINT = os.getenv("BIFROST_ENDPOINT", "http://bifrost.agents:8080")
MODEL_ALIAS = os.getenv("BIFROST_MODEL_ALIAS", "bedrock/anthropic.claude-sonnet-5-v2-20260715")

model = OpenAIModel(
    client_args={
        "base_url": f"{BIFROST_ENDPOINT}/v1",
        "api_key": "bifrost-internal",
    },
    model_id=MODEL_ALIAS,
)

agent = Agent(
    model=model,
    system_prompt=(
        "You are a financial research agent specialising in market analysis. "
        "Use the web_search tool to find current market data and the summarize "
        "tool to condense long findings into actionable insights."
    ),
    tools=[web_search, summarize],
)

# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------
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
    """Invoke the research agent. Strands SDK auto-instruments the call,
    creating spans for every LLM invocation and tool call. Bifrost contributes
    correlated child spans with token counts and cost attributes."""
    try:
        result = agent(request.query)

        usage = getattr(result, "usage", None)
        return InvokeResponse(
            response=str(result),
            tokens_input=usage.input_tokens if usage else 0,
            tokens_output=usage.output_tokens if usage else 0,
        )
    except Exception as e:
        logger.error("Agent invocation failed: %s", e)
        raise HTTPException(status_code=500, detail=str(e))
