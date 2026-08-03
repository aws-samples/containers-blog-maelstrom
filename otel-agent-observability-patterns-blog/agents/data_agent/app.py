"""FastAPI application for the data agent with OTEL instrumentation."""

import os
import logging
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from opentelemetry import trace

from agents.shared.otel_bootstrap import init_otel

tracer = init_otel("data-agent")

from strands import Agent
from strands.models.bedrock import BedrockModel

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

BIFROST_ENDPOINT = os.getenv("BIFROST_ENDPOINT", "http://bifrost.agents:8080")

model = BedrockModel(
    model_id=os.getenv("BEDROCK_PRIMARY_MODEL", "us.anthropic.claude-sonnet-4-6-20260514"),
    region_name=os.getenv("AWS_REGION", "us-west-2"),
    endpoint_url=BIFROST_ENDPOINT if os.getenv("USE_BIFROST", "true") == "true" else None,
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
