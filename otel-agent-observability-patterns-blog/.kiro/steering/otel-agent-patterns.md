---
inclusion: always
---

# OTEL Agent Observability Patterns — Project Steering

## Canonical Architecture

Two observability patterns for AI agents on Amazon EKS. The patterns differ in **how telemetry
is collected** — not where it lands. Both use Langfuse as the single destination. Both require a
single correlated trace in Langfuse that unifies agent spans and Bifrost LLM spans.

### What is shared across both patterns

- **Bifrost** is the LLM gateway for all agent calls in both patterns. Agents never call Bedrock
  directly. All LLM traffic flows: Agent → Bifrost → Bedrock.
- **Langfuse** is the single observability destination for both patterns: traces, LLM cost,
  token usage, prompt analytics, session tracking.
- **Trace correlation** is required in both patterns. Bifrost reads the W3C `traceparent` header
  from the inbound agent request and creates a child span under the same trace ID. The result is
  a single unified trace in Langfuse: agent reasoning spans + Bifrost LLM call spans.
- **AMP and AMG are not used.** No Amazon Managed Prometheus, no Amazon Managed Grafana.
- **ADOT is not used.** No ADOT DaemonSet, no auto-instrumentation CR.

---

## Pattern 1 — Decentralized (Framework-level collection)

The agent uses **Strands SDK built-in telemetry**. No explicit OTEL SDK spans in agent code.
The framework auto-instruments LLM calls, tool calls, and reasoning steps. Telemetry is exported
directly from the agent pod to Langfuse — no OTEL Collector in this path.

```
Agent Pod
  ├── Strands SDK built-in telemetry (auto-instruments LLM + tool calls)
  ├── LLM call → Bifrost (W3C traceparent propagated via httpx instrumentation)
  │     └── Bifrost → Bedrock
  │
  ├── Agent OTLP ──────────────────────────────────────────► Langfuse
  └── Bifrost OTLP ────────────────────────────────────────► Langfuse
                                                   (unified trace: agent + LLM spans)
```

Key characteristics:
- Agent code has no explicit `tracer.start_span()` calls — Strands handles instrumentation
- `HTTPXClientInstrumentor` injects `traceparent` into outbound Bifrost requests automatically
- Bifrost OTEL plugin reads `traceparent`, creates child spans, ships to Langfuse directly
- Both agent and Bifrost export OTLP to Langfuse independently using the same trace ID
- No shared collector infrastructure — each component owns its own export path
- Developer experience: framework does the work, minimal agent code changes

---

## Pattern 2 — Centralized (OTEL SDK + Collector)

The agent uses the **explicit OpenTelemetry SDK**. Developers manually create spans, set
semantic attributes, and control exactly what gets traced. All telemetry — from agents and from
Bifrost — flows through a shared OTEL Collector before reaching Langfuse.

```
Agent Pod
  ├── Explicit OTEL SDK spans (developer-controlled: agent.invoke, tool.call, etc.)
  ├── LLM call → Bifrost (W3C traceparent propagated via httpx instrumentation)
  │     └── Bifrost → Bedrock
  │
  ├── Agent OTLP ──────────────────────────────────────────► OTEL Collector
  └── Bifrost OTLP ────────────────────────────────────────► OTEL Collector
                                                                    │
                                                                    ▼
                                                               Langfuse
                                                   (unified trace: agent + LLM spans)
```

Key characteristics:
- Agent code explicitly creates spans with semantic attributes (token counts, model ID, cost)
- `HTTPXClientInstrumentor` injects `traceparent` into outbound Bifrost requests automatically
- Bifrost OTEL plugin reads `traceparent`, creates child spans, ships to OTEL Collector
- OTEL Collector batches, enriches, and forwards all telemetry to Langfuse
- Single egress point — the Collector controls what reaches Langfuse
- Developer experience: full control over trace shape, attributes, and cardinality
- Collector gives you: batching, attribute enrichment, future backend flexibility

---

## Trace Correlation — How It Works (Both Patterns)

The mechanism is identical in both patterns. The W3C `traceparent` header is the correlation key.

1. Agent starts a trace and opens a root span (either via Strands auto-instrumentation or explicit SDK)
2. `HTTPXClientInstrumentor` intercepts the outbound HTTP call to Bifrost and injects `traceparent`
3. Bifrost's OTEL plugin reads `traceparent`, extracts the trace ID and parent span ID
4. Bifrost creates a child span under the same trace ID for the Bedrock `InvokeModel` call
5. Both agent spans and Bifrost child spans are exported to Langfuse (directly or via Collector)
6. Langfuse reconstructs the full tree under one trace ID

Result in Langfuse for a single agent invocation:
```
Trace: research-agent | 3.2s | $0.0043
├── agent.invoke ────────────────────────────────────────── 3.2s
│   ├── tool.call: web_search ──────────────────────────── 0.8s
│   ├── [Bifrost] bedrock.invoke: claude-sonnet-5 ─────── 1.2s  ← Bifrost child span
│   │     input_tokens: 450, output_tokens: 280, cost: $0.0026
│   ├── tool.call: summarize ───────────────────────────── 0.3s
│   └── [Bifrost] bedrock.invoke: claude-sonnet-5 ─────── 0.9s  ← Bifrost child span
│         input_tokens: 620, output_tokens: 150, cost: $0.0017
```

---

## Langfuse — What It Shows for Both Patterns

Langfuse is the authoritative observability surface. Both patterns produce the same unified view:

| Signal | Source | Langfuse View |
|---|---|---|
| Agent reasoning trace | Strands SDK (P1) or OTEL SDK (P2) | Full trace tree per invocation |
| Tool call spans | Strands SDK (P1) or OTEL SDK (P2) | Child spans under agent.invoke |
| LLM call spans | Bifrost OTEL plugin | Child spans under agent.invoke |
| Token usage (input/output) | Bifrost span attributes | Per-generation token counts |
| LLM cost attribution | Bifrost span attributes | Per-request and session cost |
| Model fallback events | Bifrost span attributes | Sonnet→Haiku fallback visible in trace |
| Prompt version tracking | Strands SDK auto-capture | Per-generation prompt snapshot |
| Session cost rollup | Langfuse aggregation | Total cost per session / per agent |

---

## What Is Removed

- **AMP (Amazon Managed Prometheus)**: not used
- **AMG (Amazon Managed Grafana)**: not used
- **ADOT DaemonSet**: not used
- **ADOT auto-instrumentation CR**: not used
- **CloudWatch GenAI Observability**: not used
- **X-Ray as a telemetry destination**: not used
- `gitops/addons/adot-collector/`: delete this folder
- `terraform/cluster/adot.tf`: delete this file
- `terraform/cluster/amp.tf`: delete this file
- `terraform/cluster/grafana.tf`: delete this file

---

## Component Responsibilities

### Bifrost
- LLM gateway for all agent calls in both patterns
- Routes to Bedrock (primary: Claude Sonnet 4.6, fallback: Claude Haiku 4.5)
- OTEL plugin reads `traceparent` and creates correlated child spans
- Exports child spans via OTLP: directly to Langfuse (Pattern 1) or to Collector (Pattern 2)
- Deployed in `agents` namespace via Helm

### Langfuse
- Single observability backend for both patterns
- Receives OTLP traces from agents and Bifrost
- `LANGFUSE_ENABLE_OTEL_INGESTION: "true"` activates `/api/public/otel` OTLP endpoint
- Authentication: HTTP Basic auth with base64(`pubkey:secretkey`) in Authorization header
- Deployed in `observability` namespace via Helm
- Credentials in `langfuse-api-keys` Kubernetes Secret

### OTEL Collector (Pattern 2 only)
- Receives OTLP from agents and Bifrost
- Single exporter: OTLP/HTTP to Langfuse
- No metrics pipeline (AMP removed)
- Deployed in `observability` namespace as a Deployment

### Agent pods
- Pattern 1: `StrandsTelemetry().setup_otlp_exporter()` with `LANGFUSE_BASE_URL` env var
- Pattern 2: explicit `TracerProvider` with `OTLPSpanExporter` pointing at Collector
- Both patterns: `HTTPXClientInstrumentor().instrument()` for `traceparent` propagation to Bifrost
- Both patterns: `OpenAIModel` client with `base_url=BIFROST_ENDPOINT/v1` for all LLM calls

---

## Environment Variables per Pattern

### Pattern 1 — Decentralized (agent pod)
```
LANGFUSE_BASE_URL=http://langfuse.observability:3000
LANGFUSE_PUBLIC_KEY=<from langfuse-api-keys secret>
LANGFUSE_SECRET_KEY=<from langfuse-api-keys secret>
BIFROST_ENDPOINT=http://bifrost.agents:8080
OTEL_PATTERN=decentralized
```

### Pattern 2 — Centralized (agent pod)
```
OTEL_EXPORTER_OTLP_ENDPOINT=http://otel-collector.observability:4317
BIFROST_ENDPOINT=http://bifrost.agents:8080
OTEL_PATTERN=centralized
```

### Bifrost (Pattern 1 — direct to Langfuse)
```
BIFROST_OTEL_COLLECTOR_URL=http://langfuse.observability:3000/api/public/otel
BIFROST_OTEL_PROTOCOL=http
BIFROST_OTEL_AUTH=Basic <base64(pubkey:secretkey)>
```

### Bifrost (Pattern 2 — via Collector)
```
BIFROST_OTEL_COLLECTOR_URL=http://otel-collector.observability:4317
BIFROST_OTEL_PROTOCOL=grpc
```

---

## Folder Structure (Target)

```
otel-agent-observability-patterns-blog/
├── config.env
├── Dockerfile
├── agents/
│   ├── shared/
│   │   └── otel_bootstrap.py        # Pattern-aware init (P1: Strands direct, P2: OTEL SDK)
│   ├── research_agent/
│   │   ├── app.py
│   │   └── tools/
│   └── data_agent/
│       ├── app.py
│       └── tools/
├── gitops/
│   ├── root/templates/
│   │   ├── 00-namespaces.yaml
│   │   ├── 06-langfuse.yaml         # Both patterns
│   │   ├── 07-bifrost.yaml          # Both patterns
│   │   ├── 08-otel-collector.yaml   # Pattern 2 only
│   │   └── 20-agents.yaml
│   └── addons/
│       ├── langfuse/
│       ├── bifrost/
│       └── agents/
├── helm-values/
│   ├── langfuse-values.yaml
│   ├── bifrost-p1-values.yaml       # Bifrost config for Pattern 1 (direct to Langfuse)
│   ├── bifrost-p2-values.yaml       # Bifrost config for Pattern 2 (to Collector)
│   └── otel-collector-values.yaml   # Pattern 2 only
├── scripts/
│   ├── setup-infra.sh
│   ├── setup-agents.sh
│   ├── verify-observability.sh
│   └── teardown.sh
└── terraform/
    ├── cluster/
    └── bootstrap/
```

---

## Blog Narrative (v3 Rewrite Guide)

### Core message
Both patterns give you the same unified trace in Langfuse. The choice is about **instrumentation
ownership**: let the framework handle it (Pattern 1) or own it with the OTEL SDK (Pattern 2).
Bifrost is always in the middle handling LLM routing and contributing its spans to the same trace.

### Pattern framing
- **Pattern 1 — Decentralized**: "Each agent is self-contained. The framework instruments
  automatically. Telemetry flows directly to Langfuse — no shared infrastructure to operate."
- **Pattern 2 — Centralized**: "All telemetry passes through a single collector. Developers
  control every span. One place to add enrichment, route to new backends, or enforce standards."

### Remove from blog
- CloudWatch GenAI Observability as a pattern or destination
- ADOT DaemonSet and auto-instrumentation
- AMP and Grafana
- "agentless" or "no OTEL instrumentation required" messaging
- Any mention of X-Ray as a telemetry destination

### Keep in blog
- Bifrost as the LLM gateway for both patterns
- Langfuse as the single destination
- Trace correlation via W3C traceparent — show the unified trace tree
- LLM cost and token attribution from Bifrost spans in Langfuse
- EKS Auto Mode, Pod Identity, ArgoCD, Terraform infrastructure story

---

## Key Constraints

- Start from scratch — do not patch existing files
- Strands SDK agents only
- EKS Auto Mode + Pod Identity
- ArgoCD GitOps for all workloads
- `config.env` is the single configuration source for all scripts
- Model IDs use `us.anthropic.*` prefix for cross-region inference
