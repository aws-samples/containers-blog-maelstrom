"""Summarize tool for the research agent.

Produces a child span under the Strands-auto-generated tool.call span.
"""

import time
import random
from strands import tool
from opentelemetry import trace

tracer = trace.get_tracer("research-agent.tools")


@tool
def summarize(text: str, max_length: int = 500) -> str:
    """Summarize a long text into a concise version.

    Args:
        text: The text to summarize.
        max_length: Maximum length of the summary in characters.

    Returns:
        A concise summary of the input text.
    """
    with tracer.start_as_current_span("summarize.execute") as span:
        span.set_attribute("tool.name", "summarize")
        span.set_attribute("tool.input_length", len(text))
        span.set_attribute("tool.max_length", max_length)

        # Simulate processing time (100-400ms)
        latency = random.uniform(0.1, 0.4)
        time.sleep(latency)

        # Simple truncation stub — in production the agent would use this
        # tool to ask the LLM to summarize, but for demo purposes we truncate
        if len(text) > max_length:
            summary = text[:max_length].rsplit(" ", 1)[0] + "..."
        else:
            summary = text

        span.set_attribute("tool.output_length", len(summary))
        span.set_attribute("tool.compression_ratio", round(len(summary) / max(len(text), 1), 2))
        span.set_attribute("tool.latency_ms", int(latency * 1000))
        span.set_attribute("tool.status", "success")
        return summary
