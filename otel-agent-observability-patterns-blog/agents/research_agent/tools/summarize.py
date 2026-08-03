"""Summarize tool for the research agent."""

from strands import tool
from opentelemetry import trace

tracer = trace.get_tracer("research-agent.tools")


@tool
def summarize(text: str, max_length: int = 500) -> str:
    """Summarize a long text into a concise version.

    Args:
        text: The text to summarize.
        max_length: Maximum length of the summary.

    Returns:
        A concise summary of the input text.
    """
    with tracer.start_as_current_span("tool.summarize") as span:
        span.set_attribute("tool.name", "summarize")
        span.set_attribute("tool.input_length", len(text))

        # The actual summarization happens via the LLM (agent delegates)
        # This tool just marks the operation in the trace
        summary = text[:max_length] if len(text) > max_length else text

        span.set_attribute("tool.output_length", len(summary))
        span.set_attribute("tool.status", "success")
        return summary
