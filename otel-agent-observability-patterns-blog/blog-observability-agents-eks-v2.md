# Decentralized vs. Centralized: Observability Patterns for AI Agents on Amazon EKS with Bifrost and Langfuse

**Authors:** Hari Muthusamy, Elamaran Shanmugam
**Channel:** Containers | **Focus Area:** Observability | **Level:** Advanced (300)
**Primary AWS Services:** Amazon EKS, Amazon Bedrock
**Feature Highlight:** EKS Pod Identity, EKS Auto Mode

---

## Introduction

As organizations deploy AI agents at scale on Kubernetes, a critical operational gap emerges: **how do you observe what your agents are actually doing?** Traditional application monitoring tells you whether a pod is healthy, but it cannot tell you why an agent hallucinated, which tool calls consumed your token budget, or where a multi-step reasoning chain broke down.

AI agents built on frameworks like Strands SDK introduce observability dimensions beyond traditional request/response patterns:

- **LLM call traces** — model invocations, token counts, latency per call, and model parameters
- **Tool/function call spans** — which tools the agent invoked, their inputs/outputs, and whether they succeeded
- **Agent reasoning chains** — the multi-step decision flow from user query to final response
- **Cost attribution** — per-agent, per-request token spend mapped back to the model and region

The question is not *whether* to instrument, but *how*: should each agent own its telemetry pipeline end-to-end (decentralized), or should a shared collection layer aggregate signals before routing them to the backend (centralized)?

In this post, we deploy two production-ready observability patterns for AI agents running on Amazon EKS. Both patterns use **Bifrost** as the LLM gateway for all agent calls and **Langfuse** as the single observability backend for traces, cost, and metrics. The difference is how telemetry is collected:

1. **Decentralized:** The Strands SDK auto-instruments agent code. Each agent exports traces directly to Langfuse — no shared collector infrastructure.
2. **Centralized:** Developers use the explicit OTEL SDK for fine-grained control. All telemetry flows through a shared OTEL Collector before reaching Langfuse.

We deploy both patterns side-by-side on the same EKS cluster, instrument the same agents with each, and show you how to choose between them. All infrastructure is provisioned with Terraform, and workloads are delivered via ArgoCD.

> **GitHub Repository:** [aws-samples/containers-blog-maelstrom/otel-agent-observability-patterns-blog](https://github.com/aws-samples/containers-blog-maelstrom/tree/main/otel-agent-observability-patterns-blog)

---

## Architecture Overview

![Architecture: Observability Patterns for AI Agents on Amazon EKS](images/architecture-diagram.png)

*Figure 1. Dual observability patterns on Amazon EKS. Both patterns route LLM calls through Bifrost and land traces in Langfuse. The decentralized path (orange) exports directly from each agent to Langfuse. The centralized path (blue) routes all telemetry through a shared OTEL Collector.*

The platform runs on Amazon EKS Auto Mode. The architecture separates into three layers:

1. **Agent layer** — Strands SDK agents, each bound to its own AgentCore capabilities (Memory, Code Interpreter, Browser) via kro claims. All LLM calls route through Bifrost.
2. **Gateway layer** — Bifrost receives every LLM request, routes to Amazon Bedrock (with model fallback), and emits correlated OTEL spans. The W3C `traceparent` header from the agent is propagated to create unified trace trees.
3. **Observability layer** — Langfuse receives traces from both agents and Bifrost (directly for Pattern 1, via Collector for Pattern 2). A single unified trace per invocation shows agent reasoning, tool calls, LLM latency, token usage, and cost.

### Trace Correlation — How It Works

The mechanism is identical in both patterns:

1. Agent starts a trace and opens a root span (via Strands auto-instrumentation or explicit OTEL SDK)
2. `HTTPXClientInstrumentor` injects `traceparent` into the outbound HTTP call to Bifrost
3. Bifrost's OTEL plugin reads `traceparent`, extracts the trace ID and parent span ID
4. Bifrost creates a child span for the Bedrock `InvokeModel` call under the same trace ID
5. Both agent spans and Bifrost child spans are exported to Langfuse
6. Langfuse reconstructs the full tree under one trace ID

The result in Langfuse for a single agent invocation:

```
Trace: research-agent | 3.2s | $0.0043
├── agent.invoke ────────────────────────────────────────── 3.2s
│   ├── tool.call: web_search ──────────────────────────── 0.8s
│   ├── [Bifrost] bedrock.invoke: claude-sonnet-5 ─────── 1.2s
│   │     input_tokens: 450, output_tokens: 280, cost: $0.0026
│   ├── tool.call: summarize ───────────────────────────── 0.3s
│   └── [Bifrost] bedrock.invoke: claude-sonnet-5 ─────── 0.9s
│         input_tokens: 620, output_tokens: 150, cost: $0.0017
```

---

## Prerequisites

- AWS account with Bedrock model access (Claude Sonnet 5 in `us-west-2`)
- Terraform >= 1.5
- `kubectl`, `helm` 3.x, AWS CLI v2
- Container runtime (Docker or Finch) for image builds

---

## Infrastructure Setup

Clone the repository and run:

```bash
git clone https://github.com/aws-samples/containers-blog-maelstrom.git
cd containers-blog-maelstrom/otel-agent-observability-patterns-blog

# Edit config.env to set your region, cluster name, and model preferences
vi config.env

./scripts/setup-infra.sh
```

The `config.env` file is the single place to configure all dynamic values:

```bash
# config.env (key settings)
export AWS_REGION=us-west-2
export EKS_CLUSTER_NAME=agent-observability
export EKS_VERSION=1.35
export BEDROCK_PRIMARY_MODEL=us.anthropic.claude-sonnet-5
export BEDROCK_FALLBACK_MODEL=us.anthropic.claude-haiku-4-5-20251001-v1:0
```

The script takes approximately 15–20 minutes and provisions:

- **EKS cluster (v1.35)** with Auto Mode and Pod Identity
- **ACK + kro EKS Capabilities** for managing AgentCore resources as Kubernetes CRs
- **ArgoCD** for GitOps delivery of all workloads (agents, Bifrost, Langfuse, OTEL Collector)

After completion, ArgoCD syncs and deploys:

| Component | What It Is | Role in This Architecture |
| --- | --- | --- |
| **Amazon EKS (v1.35)** | AWS-managed Kubernetes with Auto Mode for compute, networking, and patching. | Runs all agent pods, Bifrost, Langfuse, and OTEL Collector. Pod Identity provides zero-credential IAM. |
| **ACK + kro** | ACK provisions AWS resources via K8s CRs. kro composes multiple ACK resources into single claims. | Declares AgentCore capabilities (Memory, Browser, CodeInterpreter) as Kubernetes-native resources. |
| **Bifrost** | High-performance LLM gateway with model routing, fallback, and OTEL integration. | Routes all agent LLM calls to Bedrock. Handles Sonnet→Haiku fallback on throttle. Emits correlated OTEL spans. |
| **Langfuse** | Open-source LLM observability platform for traces, cost tracking, prompt analytics. | Single observability backend for both patterns. Receives traces via OTLP, shows cost, token usage, and quality. |
| **OTEL Collector** | Vendor-neutral OpenTelemetry Collector for receiving, processing, and exporting telemetry. | Pattern 2 only. Aggregates telemetry from agents and Bifrost before forwarding to Langfuse. |
| **ArgoCD** | Declarative GitOps continuous delivery for Kubernetes. | Manages all workloads — a git commit triggers a rollout. |

### Configure Langfuse Credentials

Langfuse is configured with **headless initialization** — the org, project, and API keys are auto-created on first boot via environment variables. No manual UI setup is required.

The pre-configured credentials are:

| | Value |
|---|---|
| **Langfuse UI login** | `admin@agent-observability.local` / `AgentObs2026!` |
| **Public Key** | `pk-lf-agent-obs-seed` |
| **Secret Key** | `sk-lf-agent-obs-seed` |

These keys are stored in the `langfuse-api-keys` Kubernetes Secret (deployed in both `observability` and `agents` namespaces) and consumed by agents and the OTEL Collector automatically.

To access the Langfuse UI:

```bash
kubectl port-forward svc/langfuse-web -n observability 3000:3000
# Open http://localhost:3000
# Login: admin@agent-observability.local / AgentObs2026!
```

---

## The Decentralized Pattern — Strands SDK Direct to Langfuse

In the decentralized pattern, the **Strands SDK built-in telemetry** handles all instrumentation. There are no explicit `tracer.start_span()` calls in agent code. The framework auto-instruments every LLM call, tool invocation, and reasoning step, then exports directly to Langfuse via OTLP. No shared collector infrastructure sits in the middle.

This pattern is "decentralized" because each agent owns its complete telemetry pipeline end-to-end. If one agent's export fails, the others are unaffected. There is no single point of failure in the collection layer.

### How It Works

```
┌──────────────────┐          ┌──────────────────┐          ┌──────────────┐
│   Agent Pod      │          │     Bifrost      │          │   Langfuse   │
│                  │          │  (LLM Gateway)   │          │              │
│  Strands SDK     │HTTP+trcpr│                  │  Bedrock │  Receives:   │
│  auto-telemetry  ├─────────▶│  reads           ├─────────▶│  • Agent     │
│                  │          │  traceparent,    │          │    spans     │
│                  │          │  creates child   │          │  • Bifrost   │
│                  │          │  spans           │          │    LLM spans │
│                  │          │                  │          │              │
│   OTLP ──────────┼──────────┼──────────────────┼─────────▶│  unified     │
│                  │          │   OTLP ──────────┼─────────▶│  trace tree  │
└──────────────────┘          └──────────────────┘          └──────────────┘
```

### Agent Code (Pattern 1)

The agent code is minimal. Telemetry setup is a single function call at startup:

```python
from agents.shared.otel_bootstrap import init_telemetry

# Bootstrap: detects LANGFUSE_BASE_URL env var → configures Strands OTLP export
init_telemetry(service_name="research-agent")

from strands import Agent
from strands.models.openai import OpenAIModel

# All LLM calls route through Bifrost
model = OpenAIModel(
    client_args={"base_url": "http://bifrost.agents:8080/v1", "api_key": "bifrost-internal"},
    model_id="bedrock/us.anthropic.claude-sonnet-5",
)

agent = Agent(model=model, tools=[web_search, summarize], system_prompt="...")
result = agent("What are the top S&P 500 sectors this quarter?")
```

The `init_telemetry()` function detects `LANGFUSE_BASE_URL` on the pod and configures Strands SDK to export OTLP traces directly to Langfuse. It also instruments httpx so the `traceparent` header propagates to Bifrost automatically.

The full implementation is at `agents/shared/otel_bootstrap.py`.

### Environment Variables (Pattern 1)

```yaml
env:
  - name: LANGFUSE_BASE_URL
    value: "http://langfuse-web.observability:3000"
  - name: LANGFUSE_PUBLIC_KEY
    valueFrom: { secretKeyRef: { name: langfuse-api-keys, key: LANGFUSE_PUBLIC_KEY } }
  - name: LANGFUSE_SECRET_KEY
    valueFrom: { secretKeyRef: { name: langfuse-api-keys, key: LANGFUSE_SECRET_KEY } }
  - name: BIFROST_ENDPOINT
    value: "http://bifrost.agents:8080"
```

---

## The Centralized Pattern — OTEL SDK + Collector to Langfuse

In the centralized pattern, developers use the **explicit OpenTelemetry SDK** for fine-grained instrumentation control. All telemetry — from agents and from Bifrost — flows through a shared OTEL Collector Deployment in the `observability` namespace before reaching Langfuse.

This pattern is "centralized" because a single collection point aggregates all telemetry. The Collector gives you batching, attribute enrichment, sampling, and a single egress point. Adding a new backend requires only a new exporter block in the Collector config — no agent code changes.

### How It Works

```
┌──────────────────┐          ┌──────────────────┐          ┌──────────────────┐
│   Agent Pod      │          │     Bifrost      │          │  OTEL Collector  │
│                  │          │  (LLM Gateway)   │          │  (observability) │
│  Explicit OTEL   │HTTP+trcpr│                  │          │                  │
│  SDK spans       ├─────────▶│  reads           │          │                  │
│                  │          │  traceparent,    │          │                  │
│                  │          │  creates child   │          │  ┌────────────┐  │
│                  │          │  spans           │          │  │  Batch +   │  │
│   OTLP ──────────┼──────────┼──────────────────┼─────────▶│  │  Forward   │  │
│                  │          │   OTLP ──────────┼─────────▶│  └─────┬──────┘  │
└──────────────────┘          └──────────────────┘          └────────┼─────────┘
                                                                     │ OTLP/HTTP
                                                                     ▼
                                                             ┌──────────────┐
                                                             │   Langfuse   │
                                                             │              │
                                                             │  unified     │
                                                             │  trace tree  │
                                                             └──────────────┘
```

### Agent Code (Pattern 2)

The same `init_telemetry()` function detects `OTEL_EXPORTER_OTLP_ENDPOINT` instead of `LANGFUSE_BASE_URL` and routes traces to the Collector:

```python
from agents.shared.otel_bootstrap import init_telemetry

# Bootstrap: detects OTEL_EXPORTER_OTLP_ENDPOINT → configures Strands OTLP to Collector
init_telemetry(service_name="research-agent")
```

The agent code is identical — the pattern switch is purely an environment variable change on the pod.

### Environment Variables (Pattern 2)

```yaml
env:
  - name: OTEL_EXPORTER_OTLP_ENDPOINT
    value: "http://otel-collector-opentelemetry-collector.observability:4318"
  - name: BIFROST_ENDPOINT
    value: "http://bifrost.agents:8080"
```

### OTEL Collector Configuration

The Collector receives OTLP from both agents and Bifrost, batches spans, and forwards to Langfuse. The `x-langfuse-ingestion-version: 4` header is required for Langfuse v3 OTLP compatibility:

```yaml
config:
  receivers:
    otlp:
      protocols:
        grpc: { endpoint: "0.0.0.0:4317" }
        http: { endpoint: "0.0.0.0:4318" }
  processors:
    batch:
      timeout: 5s
      send_batch_size: 256
  exporters:
    otlphttp/langfuse:
      endpoint: "http://langfuse-web.observability:3000/api/public/otel"
      headers:
        Authorization: "Basic ${env:LANGFUSE_AUTH_TOKEN}"
        x-langfuse-ingestion-version: "4"
  service:
    pipelines:
      traces:
        receivers: [otlp]
        processors: [batch]
        exporters: [otlphttp/langfuse]
```

---

## Bifrost — LLM Gateway for Both Patterns

Bifrost sits between every agent and Amazon Bedrock in both patterns. It is not an observability-specific component — it is the LLM routing layer that also contributes correlated telemetry.

### What Bifrost Does

1. **Model routing** — receives OpenAI-compatible `/v1/chat/completions` requests and routes them to Bedrock models using the `bedrock/` prefix in the model ID.
2. **Fallback** — if the primary model (Claude Sonnet 5) is throttled, Bifrost automatically falls back to the configured secondary (Claude Haiku 4.5).
3. **Trace correlation** — the OTEL plugin reads the inbound `traceparent` header and creates a child span with LLM-specific attributes (model, tokens, latency, cost).
4. **Cost attribution** — Bifrost calculates per-request cost based on model pricing and attaches it as a span attribute visible in Langfuse.

### Bifrost OTEL Plugin Configuration

The Bifrost OTEL plugin target determines where its spans go:

- **Pattern 1:** Bifrost sends spans directly to Langfuse (`http://langfuse-web.observability:3000/api/public/otel/v1/traces`)
- **Pattern 2:** Bifrost sends spans to the OTEL Collector (`otel-collector-opentelemetry-collector.observability:4318`)

The plugin is configured via the Bifrost seed job (`gitops/addons/bifrost/seed-provider-job.yaml`) which runs after Bifrost boots:

```yaml
# Bifrost OTEL plugin config (set via seed job)
plugins:
  otel:
    enabled: true
    config:
      service_name: "bifrost"
      collector_url: "http://langfuse-web.observability:3000/api/public/otel/v1/traces"
      trace_type: "genai_extension"
      protocol: "http"
      headers:
        Authorization: "Basic <base64(pubkey:secretkey)>"
        x-langfuse-ingestion-version: "4"
```

To switch to Pattern 2, update the seed job's `OTEL_TARGET` to point at the Collector:

```yaml
collector_url: "http://otel-collector-opentelemetry-collector.observability:4318/v1/traces"
```

---

## Deploying the Agents

Build images and let ArgoCD deploy:

```bash
./scripts/setup-agents.sh
```

ArgoCD detects the new image tags, syncs the Deployments, and rolls out pods. Verify:

```bash
kubectl get pods -n agents
```

### Running Queries

```bash
kubectl port-forward svc/research-agent -n agents 8080:8080 &

# Simple research query (LLM call + tool calls)
curl -s -X POST http://localhost:8080/invoke \
  -H "Content-Type: application/json" \
  -d '{"query": "What are the top 3 performing S&P 500 sectors this quarter?"}' | jq .

# Multi-step analysis
curl -s -X POST http://localhost:8080/invoke \
  -H "Content-Type: application/json" \
  -d '{"query": "Compare NVIDIA and AMD stock performance over the last 6 months."}' | jq .
```

Each query produces a unified trace in Langfuse showing the full reasoning chain with correlated Bifrost LLM spans.

---

## Viewing Traces in Langfuse

Open the Langfuse UI and navigate to Traces. Each agent invocation appears as a single trace with the full span tree:

- **Root span:** `agent.invoke` with the user query
- **Tool spans:** `tool.call: web_search`, `tool.call: summarize` as children
- **LLM spans (from Bifrost):** `bedrock.invoke: claude-sonnet-5` as children of the agent span, each with:
  - `input_tokens`, `output_tokens` — exact token counts
  - `cost` — dollar amount for that specific generation
  - `model` — which model actually served the request (visible when fallback occurs)
  - `latency` — time spent waiting for Bedrock

Langfuse aggregates this data across all traces to surface:

- **Cost per agent** — which agents consume the most budget
- **Cost per session** — multi-turn conversation cost tracking
- **Model fallback visibility** — when Sonnet→Haiku fallback occurs, it is visible in the trace
- **Token usage trends** — input vs. output token rates over time
- **Prompt version tracking** — Strands SDK captures prompt snapshots automatically

---

## When to Use Which Pattern

| Dimension | Decentralized (Strands Direct) | Centralized (OTEL Collector) |
| --- | --- | --- |
| **Instrumentation** | Framework auto-instruments — no custom spans | Developer writes explicit spans and attributes |
| **Collection topology** | Each agent exports independently to Langfuse | All telemetry flows through a shared Collector |
| **Setup effort** | Minimal — set env vars, framework does the rest | Moderate — deploy Collector, configure pipelines |
| **Failure isolation** | One agent's export failure does not affect others | Collector is a shared dependency |
| **Extensibility** | Add backends = change each agent's config | Add backends = add an exporter to Collector config |
| **Control over traces** | Framework decides what to trace | Developer decides span boundaries and attributes |
| **Best for** | Teams that want fast setup and framework defaults | Teams that need custom attributes, sampling, or multi-backend routing |

Both patterns produce the **same unified trace** in Langfuse. The Bifrost LLM spans are identical regardless of pattern. The only difference is who creates the agent-side spans (framework vs. developer) and how they reach Langfuse (direct vs. via Collector).

---

## Switching Between Patterns

The repository deploys both patterns simultaneously — the `research-agent` uses Pattern 1 (Decentralized) and the `data-agent` uses Pattern 2 (Centralized). To switch a specific agent's pattern, change its environment variables in the deployment template (`gitops/addons/agents/values.yaml`):

```yaml
agents:
  - name: research-agent
    pattern: decentralized   # Pattern 1: direct to Langfuse
  - name: data-agent
    pattern: centralized     # Pattern 2: via OTEL Collector
```

Commit the change to git → ArgoCD syncs → pods restart with new env vars → traces flow through the new path. Langfuse shows the same unified trace either way.

---

## Cleanup

```bash
./scripts/teardown.sh
```

The teardown script deletes agent workloads first (triggering ACK resource cleanup), waits for AWS-side deletes to complete, and then destroys the Terraform stacks. If an ACK resource gets stuck in `Deleting`, clear the finalizer:

```bash
kubectl patch <kind>/<name> -n agents \
  -p '{"metadata":{"finalizers":null}}' --type=merge
```

---

## Conclusion

Observability for AI agents requires more than pod health checks. You need to see the full reasoning chain — which tools were called, how many tokens each LLM call consumed, what it cost, and whether the model fell back to a cheaper alternative.

The two patterns in this post give you that visibility with different tradeoffs:

- **Decentralized** — let the Strands SDK handle instrumentation. Each agent exports directly to Langfuse. Fast to set up, zero shared infrastructure, framework-level traces out of the box.
- **Centralized** — own the instrumentation with the OTEL SDK. Route everything through a Collector. Full control over span shapes, attributes, sampling, and future backend flexibility.

Both patterns use Bifrost as the LLM gateway for every agent call. Bifrost handles model routing and fallback while contributing correlated OTEL spans with token counts and cost. Both patterns land in Langfuse, producing the same unified trace tree per invocation.

The complete implementation — Terraform, ArgoCD GitOps manifests, agent code, and OTEL configuration — is available at the [AWS Samples GitHub repository](https://github.com/aws-samples/containers-blog-maelstrom/tree/main/otel-agent-observability-patterns-blog).

---

## References

- [Langfuse OTEL Integration](https://langfuse.com/docs/integrations/opentelemetry)
- [Bifrost LLM Gateway](https://github.com/maximhq/bifrost)
- [AWS Controllers for Kubernetes (ACK)](https://aws-controllers-k8s.github.io/community/)
- [kro — Kube Resource Orchestrator](https://kro.run/)
- [EKS Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/automode.html)
- [Strands Agents SDK](https://github.com/strands-agents/sdk-python)
- [OpenTelemetry Collector](https://opentelemetry.io/docs/collector/)
- [Multi-Agent Systems for Financial Services on Amazon EKS and AgentCore](https://aws.amazon.com/blogs/industries/multi-agent-systems-for-financial-services-on-amazon-eks-and-agentcore/)
