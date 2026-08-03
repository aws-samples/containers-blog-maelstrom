"""Web search tool for the research agent."""

import httpx
from strands import tool
from opentelemetry import trace

tracer = trace.get_tracer("research-agent.tools")


@tool
def web_search(query: str) -> str:
    """Search the web for current information about a topic.

    Args:
        query: The search query string.

    Returns:
        A summary of search results.
    """
    with tracer.start_as_current_span("tool.web_search") as span:
        span.set_attribute("tool.name", "web_search")
        span.set_attribute("tool.input", query[:200])

        # Stub implementation — replace with real search API
        # In production, this would call a search API or MCP tool
        result = f"[Search results for: {query}] "
        result += "Based on current market data, the S&P 500 has shown "
        result += "mixed performance across sectors this quarter. "
        result += "Technology and healthcare continue to lead gains."

        span.set_attribute("tool.output_length", len(result))
        span.set_attribute("tool.status", "success")
        return result
