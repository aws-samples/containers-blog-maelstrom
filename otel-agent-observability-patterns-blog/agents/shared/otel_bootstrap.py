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

    try:
        from strands.telemetry import StrandsTelemetry
        StrandsTelemetry().setup_otlp_exporter()
        logger.info(
            "[otel_bootstrap] Pattern 1 (Decentralized): Strands → Langfuse OTLP "
            "service=%s endpoint=%s/api/public/otel",
            service_name, langfuse_url,
        )
    except ImportError:
        logger.warning("[otel_bootstrap] strands.telemetry not available — skipping setup")


def _init_collector(service_name: str, otlp_endpoint: str) -> None:
    """Pattern 2: Strands SDK sends OTLP traces to the shared OTEL Collector."""
    try:
        from strands.telemetry import StrandsTelemetry
        StrandsTelemetry().setup_otlp_exporter()
        logger.info(
            "[otel_bootstrap] Pattern 2 (Centralized): Strands → Collector OTLP "
            "service=%s endpoint=%s",
            service_name, otlp_endpoint,
        )
    except ImportError:
        logger.warning("[otel_bootstrap] strands.telemetry not available — skipping setup")


def _instrument_http_clients() -> None:
    """Instrument httpx so Bifrost receives W3C traceparent on every LLM call."""
    try:
        from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
        HTTPXClientInstrumentor().instrument()
    except ImportError:
        logger.debug("[otel_bootstrap] opentelemetry-instrumentation-httpx not installed")
