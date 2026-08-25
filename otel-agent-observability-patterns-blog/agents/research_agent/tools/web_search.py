"""Web search tool for the research agent.

Produces a child span under the Strands-auto-generated tool.call span,
showing how custom OTEL spans nest inside framework-level instrumentation.
"""

import time
import random
from strands import tool
from opentelemetry import trace

tracer = trace.get_tracer("research-agent.tools")


@tool
def web_search(query: str) -> str:
    """Search the web for current information about a topic.

    Args:
        query: The search query string.

    Returns:
        A summary of search results relevant to the query.
    """
    with tracer.start_as_current_span("web_search.execute") as span:
        span.set_attribute("tool.name", "web_search")
        span.set_attribute("tool.query", query[:200])

        # Simulate network latency (200-800ms) so traces have visible duration
        latency = random.uniform(0.2, 0.8)
        time.sleep(latency)

        # Stub results — in production, call a search API or MCP tool
        results = [
            f"[1] Market analysis for: {query}",
            "The S&P 500 posted a 2.3% gain this quarter led by technology (+4.1%) and healthcare (+3.8%).",
            "NVIDIA reported record revenue of $44.6B driven by data center demand.",
            "The Federal Reserve maintained rates at 4.25-4.50% citing stable inflation metrics.",
            "AMD gained 18% on strong AI chip shipment forecasts for Q3 2026.",
        ]
        result = " ".join(results)

        span.set_attribute("tool.results_count", len(results))
        span.set_attribute("tool.output_length", len(result))
        span.set_attribute("tool.latency_ms", int(latency * 1000))
        span.set_attribute("tool.status", "success")
        return result
