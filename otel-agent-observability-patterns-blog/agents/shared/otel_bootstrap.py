"""Shared OTEL initialization with dual-export for all agents."""

import os
from opentelemetry import trace
from opentelemetry.sdk.trace import TracerProvider
from opentelemetry.sdk.trace.export import BatchSpanProcessor
from opentelemetry.exporter.otlp.proto.grpc.trace_exporter import OTLPSpanExporter
from opentelemetry.sdk.resources import Resource
from opentelemetry.semconv.resource import ResourceAttributes
from opentelemetry.instrumentation.requests import RequestsInstrumentor
from opentelemetry.instrumentation.botocore import BotocoreInstrumentor


def init_otel(service_name: str):
    """Initialize OTEL with dual export to ADOT and self-hosted Collector.

    Pattern 1 (Decentralized): ADOT DaemonSet on localhost:4317 -> CloudWatch GenAI
    Pattern 2 (Centralized): OTEL Collector ClusterIP -> Langfuse + AMP
    """
    resource = Resource.create({
        ResourceAttributes.SERVICE_NAME: service_name,
        ResourceAttributes.SERVICE_NAMESPACE: "agent-observability",
        "agent.framework": "strands-sdk",
        "deployment.environment": os.getenv("ENVIRONMENT", "production"),
    })

    provider = TracerProvider(resource=resource)

    # Pattern 1: Export to ADOT (DaemonSet, auto-injected via managed add-on)
    adot_endpoint = os.getenv("ADOT_ENDPOINT", "http://localhost:4317")
    provider.add_span_processor(BatchSpanProcessor(
        OTLPSpanExporter(endpoint=adot_endpoint, insecure=True)
    ))

    # Pattern 2: Export to self-hosted OTEL Collector
    collector_endpoint = os.getenv(
        "OTEL_COLLECTOR_ENDPOINT", "http://otel-collector.observability:4317"
    )
    if collector_endpoint:
        provider.add_span_processor(BatchSpanProcessor(
            OTLPSpanExporter(endpoint=collector_endpoint, insecure=True)
        ))

    trace.set_tracer_provider(provider)

    # Auto-instrument HTTP clients and AWS SDK calls
    RequestsInstrumentor().instrument()
    BotocoreInstrumentor().instrument()

    # -- HTTP client instrumentation (W3C traceparent propagation) --
    # Instruments httpx so outbound calls to Bifrost carry the traceparent header.
    # Bifrost reads traceparent and creates child spans under the same trace ID,
    # producing a unified trace tree: Agent -> Bifrost LLM call.
    try:
        from opentelemetry.instrumentation.httpx import HTTPXClientInstrumentor
        HTTPXClientInstrumentor().instrument()
    except ImportError:
        pass

    return trace.get_tracer(service_name)
