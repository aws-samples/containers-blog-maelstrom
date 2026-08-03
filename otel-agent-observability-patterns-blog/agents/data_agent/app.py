"""FastAPI application for the data agent with OTEL instrumentation."""

import os
import logging
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from opentelemetry import trace

from agents.shared.otel_bootstrap import init_otel

tracer = init_otel("data-agent")

from strands import Agent
from strands.models.openai import OpenAIModel

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# Route through Bifrost (OpenAI-compatible LLM gateway)
BIFROST_ENDPOINT = os.getenv("BIFROST_ENDPOINT", "http://bifrost.agents:8080")
MODEL_ALIAS = os.getenv("BIFROST_MODEL_ALIAS", "bedrock/us.anthropic.claude-sonnet-4-6")

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
    """Invoke the data agent with a user query."""
    with tracer.start_as_current_span("agent.invoke") as span:
        span.set_attribute("agent.name", "data-agent")
        span.set_attribute("agent.query", request.query[:200])

        try:
            result = agent(request.query)
            input_tokens = getattr(getattr(result, "usage", None), "input_tokens", 0)
            output_tokens = getattr(getattr(result, "usage", None), "output_tokens", 0)

            span.set_attribute("llm.token_count.input", input_tokens)
            span.set_attribute("llm.token_count.output", output_tokens)
            span.set_attribute("llm.model_id", MODEL_ALIAS)
            span.set_attribute("llm.gateway", "bifrost")
            span.set_status(trace.StatusCode.OK)

            return InvokeResponse(
                response=str(result),
                tokens_input=input_tokens,
                tokens_output=output_tokens,
            )
        except Exception as e:
            span.set_status(trace.StatusCode.ERROR, str(e))
            span.record_exception(e)
            raise HTTPException(status_code=500, detail=str(e))
