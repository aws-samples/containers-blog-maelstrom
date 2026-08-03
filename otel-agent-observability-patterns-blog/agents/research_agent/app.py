"""FastAPI application for the research agent with OTEL instrumentation."""

import os
import logging
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from opentelemetry import trace

# Initialize OTEL before anything else
from agents.shared.otel_bootstrap import init_otel

tracer = init_otel("research-agent")

from strands import Agent
from strands.models.bedrock import BedrockModel
from agents.research_agent.tools.web_search import web_search
from agents.research_agent.tools.summarize import summarize

logging.basicConfig(level=logging.INFO)
logger = logging.getLogger(__name__)

# --- Agent setup ---
# FIX 4: Route through Bifrost proxy instead of direct Bedrock
BIFROST_ENDPOINT = os.getenv("BIFROST_ENDPOINT", "http://bifrost.agents:8080")

model = BedrockModel(
    model_id=os.getenv("BEDROCK_PRIMARY_MODEL", "us.anthropic.claude-sonnet-4-6-20260514"),
    region_name=os.getenv("AWS_REGION", "us-west-2"),
    # When Bifrost is configured as an OpenAI-compatible proxy,
    # the Strands SDK routes through it via the endpoint override.
    # Bifrost handles model routing, fallback, and cost tracking.
    endpoint_url=BIFROST_ENDPOINT if os.getenv("USE_BIFROST", "true") == "true" else None,
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
    with tracer.start_as_current_span("agent.invoke") as span:
        span.set_attribute("agent.name", "research-agent")
        span.set_attribute("agent.query", request.query[:200])

        try:
            result = agent(request.query)

            tokens_in = getattr(result, "usage", None)
            tokens_out = getattr(result, "usage", None)
            input_tokens = tokens_in.input_tokens if tokens_in else 0
            output_tokens = tokens_out.output_tokens if tokens_out else 0

            span.set_attribute("llm.token_count.input", input_tokens)
            span.set_attribute("llm.token_count.output", output_tokens)
            span.set_attribute("llm.model_id", os.getenv("BEDROCK_PRIMARY_MODEL", "us.anthropic.claude-sonnet-4-6-20260514"))
            span.set_status(trace.StatusCode.OK)

            return InvokeResponse(
                response=str(result),
                tokens_input=input_tokens,
                tokens_output=output_tokens,
            )
        except Exception as e:
            span.set_status(trace.StatusCode.ERROR, str(e))
            span.record_exception(e)
            logger.error(f"Agent invocation failed: {e}")
            raise HTTPException(status_code=500, detail=str(e))
