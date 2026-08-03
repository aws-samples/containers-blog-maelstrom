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
            logger.error(f"Agent invocation failed: {e}")
            raise HTTPException(status_code=500, detail=str(e))
