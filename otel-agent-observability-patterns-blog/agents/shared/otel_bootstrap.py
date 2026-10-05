"""Shared OTEL initialization — pattern-aware telemetry setup for all agents.

Pattern 1 (Decentralized):
  Agent sends traces directly to Langfuse via OTLP/HTTP using Strands SDK
  built-in telemetry. Set LANGFUSE_BASE_URL, LANGFUSE_PUBLIC_KEY,
  LANGFUSE_SECRET_KEY on the agent pod.

Pattern 2 (Centralized):
  Agent sends traces to a shared OTEL Collector via OTLP/gRPC.
  Set OTEL_EXPORTER_OTLP_ENDPOINT on the agent pod.

Both patterns:
  - Bifrost is the LLM gateway for all calls (BIFROST_ENDPOINT)
  - HTTPXClientInstrumentor propagates W3C traceparent to Bifrost so its
    child spans correlate with agent spans in Langfuse
"""

import os
import base64
import logging

logger = logging.getLogger(__name__)

# Low-value "noise" spans dropped from the blog's trace view, matched on the
# span name (case-insensitive substring). The Strands SDK emits an
# event-loop-cycle span per reasoning iteration (internal orchestration) that
# adds no signal beyond the major items — agent invocation (root), tool calls,
# and the model/LLM spans. Kept deliberately narrow so model/tool spans are
# never caught. The raw httpx client span is dropped separately by its
# instrumentation scope (see _keep_span) — NOT by name, since dropping its
# export does not affect W3C traceparent propagation to Bifrost (the header is
# injected regardless), so Bifrost spans still correlate into the same trace.
# Toggle OTEL_KEEP_ALL_SPANS=true to see the full, unfiltered tree.
_NOISE_SPAN_FRAGMENTS = ("event_loop", "cycle")
_NOISE_SCOPE_FRAGMENTS = ("instrumentation.httpx",)


def _keep_span(span) -> bool:
    """Return False for low-value 'noise' spans so they are not exported.

    Keeps the major items: agent invocation (root), tool calls, and model/LLM
    spans. Drops the Strands event-loop-cycle spans and the httpx client span.
    Set OTEL_KEEP_ALL_SPANS=true to disable filtering and see the full tree.
    """
    if os.getenv("OTEL_KEEP_ALL_SPANS", "").lower() in ("1", "true", "yes"):
        return True
    name = (span.name or "").lower()
    if any(frag in name for frag in _NOISE_SPAN_FRAGMENTS):
        return False
    # Drop the raw httpx client span by its instrumentation scope. Context
    # propagation (traceparent to Bifrost) is unaffected — only export is.
    scope = getattr(span, "instrumentation_scope", None)
    scope_name = (getattr(scope, "name", "") or "").lower()
    if any(frag in scope_name for frag in _NOISE_SCOPE_FRAGMENTS):
        return False
    return True


def _build_filtering_processor():
    """Build a BatchSpanProcessor whose on_end drops noise spans before export.

    Returns None if the OTEL SDK/exporter is unavailable (telemetry becomes a
    no-op). The OTLP endpoint/headers are read from the environment by the
    exporter, exactly as the standard OTEL SDK does.
    """
    try:
        from opentelemetry.sdk.trace.export import BatchSpanProcessor
        from opentelemetry.exporter.otlp.proto.http.trace_exporter import (
            OTLPSpanExporter,
        )
    except ImportError:
        logger.warning("[otel_bootstrap] OTEL SDK/exporter not installed — telemetry disabled")
        return None

    class _FilteringBatchSpanProcessor(BatchSpanProcessor):
        def on_end(self, span):
            if _keep_span(span):
                super().on_end(span)

    return _FilteringBatchSpanProcessor(OTLPSpanExporter())


def _setup_strands_with_filter(service_name: str) -> None:
    """Register a global TracerProvider with a noise-filtering OTLP pipeline and
    hand the SAME provider to the Strands SDK, so Strands emits spans into our
    filtered pipeline rather than creating its own unfiltered exporter.

    Important: passing tracer_provider= to StrandsTelemetry does NOT make it the
    global provider on its own, so we set it global explicitly — otherwise the
    agent's tracer resolves to the default (no-op) provider and nothing exports.
    """
    try:
        from opentelemetry import trace as _trace
        from opentelemetry.sdk.trace import TracerProvider
        from strands.telemetry import StrandsTelemetry
        from strands.telemetry.config import get_otel_resource
    except ImportError:
        logger.warning("[otel_bootstrap] strands.telemetry not available — skipping setup")
        return

    processor = _build_filtering_processor()
    if processor is None:
        return

    provider = TracerProvider(resource=get_otel_resource())
    provider.add_span_processor(processor)

    # Make our provider the global one so Strands (and any OTel tracer) uses it.
    _trace.set_tracer_provider(provider)
    # Hand the same provider to Strands (sets up propagators); do NOT call
    # setup_otlp_exporter(), which would attach a second, unfiltered exporter.
    StrandsTelemetry(tracer_provider=provider)


def init_telemetry(service_name: str) -> None:
    """Configure OTLP export based on env vars present on the pod.

    Priority:
      1. LANGFUSE_BASE_URL  → Pattern 1: direct Strands→Langfuse OTLP
      2. OTEL_EXPORTER_OTLP_ENDPOINT → Pattern 2: Strands→Collector OTLP
      3. Neither set → no-op (telemetry silently disabled)
    """
    langfuse_url = os.getenv("LANGFUSE_BASE_URL")
    otlp_endpoint = os.getenv("OTEL_EXPORTER_OTLP_ENDPOINT")

    if langfuse_url:
        _init_langfuse_direct(service_name, langfuse_url)
    elif otlp_endpoint:
        _init_collector(service_name, otlp_endpoint)
    else:
        logger.warning(
            "[otel_bootstrap] No telemetry destination configured. "
            "Set LANGFUSE_BASE_URL (Pattern 1) or "
            "OTEL_EXPORTER_OTLP_ENDPOINT (Pattern 2)."
        )
        return

    # Instrument httpx so outbound calls to Bifrost carry W3C traceparent.
    # Bifrost reads traceparent and creates a child span under the same trace
    # ID — producing a unified trace tree in Langfuse: agent + Bifrost spans.
    _instrument_http_clients()


def _init_langfuse_direct(service_name: str, langfuse_url: str) -> None:
    """Pattern 1: Strands SDK sends OTLP traces directly to Langfuse.

    Langfuse OTLP endpoint uses HTTP Basic auth:
      Authorization: Basic base64(PUBLIC_KEY:SECRET_KEY)
    """
    public_key = os.getenv("LANGFUSE_PUBLIC_KEY", "")
    secret_key = os.getenv("LANGFUSE_SECRET_KEY", "")

    if not public_key or not secret_key:
        logger.warning(
            "[otel_bootstrap] LANGFUSE_BASE_URL is set but "
            "LANGFUSE_PUBLIC_KEY / LANGFUSE_SECRET_KEY are missing."
        )

    auth_token = base64.b64encode(f"{public_key}:{secret_key}".encode()).decode()

    os.environ["OTEL_EXPORTER_OTLP_ENDPOINT"] = f"{langfuse_url}/api/public/otel"
    os.environ["OTEL_EXPORTER_OTLP_HEADERS"] = (
        f"Authorization=Basic {auth_token},"
        "x-langfuse-ingestion-version=4"
    )

    _setup_strands_with_filter(service_name)
    logger.info(
        "[otel_bootstrap] Pattern 1 (Decentralized): Strands → Langfuse OTLP "
        "service=%s endpoint=%s/api/public/otel (noise spans filtered)",
        service_name, langfuse_url,
    )


def _init_collector(service_name: str, otlp_endpoint: str) -> None:
    """Pattern 2: Strands SDK sends OTLP traces to the shared OTEL Collector.

    Note: in the centralized pattern the Collector can also filter spans, but
    we apply the same client-side filter so both patterns produce an equivalent
    trace shape in Langfuse.
    """
    _setup_strands_with_filter(service_name)
    logger.info(
        "[otel_bootstrap] Pattern 2 (Centralized): Strands → Collector OTLP "
        "service=%s endpoint=%s (noise spans filtered)",
        service_name, otlp_endpoint,
    )


def _instrument_http_clients() -> None:
    """Instrument httpx so Bifrost receives W3C traceparent on every LLM call."""
    try:
        from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
        HTTPXClientInstrumentor().instrument()
    except ImportError:
        logger.debug("[otel_bootstrap] opentelemetry-instrumentation-httpx not installed")
