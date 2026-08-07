"""Data agent — Strands SDK agent instrumented for both observability patterns.

Same telemetry bootstrap as all agents — pattern determined by env vars.
All LLM calls route through Bifrost with W3C traceparent propagation.
"""

import os
import logging
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel

from agents.shared.otel_bootstrap import init_telemetry

init_telemetry(service_name=os.getenv("OTEL_SERVICE_NAME", "data-agent"))

from strands import Agent                      # noqa: E402
from strands.models.openai import OpenAIModel  # noqa: E402

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# ---------------------------------------------------------------------------
# Bifrost LLM gateway
# ---------------------------------------------------------------------------
BIFROST_ENDPOINT = os.getenv("BIFROST_ENDPOINT", "http://bifrost.agents:8080")
MODEL_ALIAS = os.getenv("BIFROST_MODEL_ALIAS", "bedrock/us.anthropic.claude-sonnet-5")

model = OpenAIModel(
    client_args={
        "base_url": f"{BIFROST_ENDPOINT}/v1",
        "api_key": "bifrost-internal",
    },
    model_id=MODEL_ALIAS,
)

agent = Agent(
    model=model,
    system_prompt="You are a data retrieval and analysis agent. Answer data questions concisely.",
    tools=[],
)

# ---------------------------------------------------------------------------
# FastAPI app
# ---------------------------------------------------------------------------
app = FastAPI(title="Data Agent", version="1.0.0")


class InvokeRequest(BaseModel):
    query: str


class InvokeResponse(BaseModel):
    response: str
    tokens_input: int = 0
    tokens_output: int = 0


@app.get("/health")
def health():
    return {"status": "healthy", "agent": "data-agent"}


@app.post("/invoke", response_model=InvokeResponse)
def invoke(request: InvokeRequest):
    """Invoke the data agent."""
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
