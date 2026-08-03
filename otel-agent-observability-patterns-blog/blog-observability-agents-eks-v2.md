# Centralized vs. Decentralized: OTEL Observability Patterns for AI Agents on Amazon EKS

**Authors:** Hari Muthusamy, Elamaran Shanmugam**Channel:** Containers | **Focus Area:** Observability | **Level:** Advanced (300)**Primary AWS Services:** Amazon EKS, Amazon CloudWatch**Feature Highlight:** EKS Pod Identity, EKS Auto Mode

---

## Introduction

As organizations deploy AI agents at scale on Kubernetes, a critical operational gap emerges: **how do you observe what your agents are actually doing?** Traditional application monitoring tells you whether a pod is healthy, but it cannot tell you why an agent hallucinated, which tool calls consumed your token budget, or where a multi-step reasoning chain broke down.

AI agents built on frameworks like Strands SDK or LangGraph introduce new observability dimensions beyond traditional request/response patterns:

- **LLM call traces** — model invocations, token counts, latency per call, and model parameters
- **Tool/function call spans** — which tools the agent invoked, their inputs/outputs, and whether they succeeded
- **Agent reasoning chains** — the multi-step decision flow from user query to final response
- **Cost attribution** — per-agent, per-request token spend mapped back to the model and region

OpenTelemetry (OTEL) provides the instrumentation standard, but the *destination* of those signals — and the operational model around them — varies significantly depending on your organization's needs.

In this post, we walk through two production-ready observability patterns for AI agents running on Amazon EKS:

1. **Decentralized:** ADOT auto-instrumentation → Amazon CloudWatch GenAI Observability
2. **Centralized:** OTEL Collector → Langfuse + Amazon Managed Prometheus → Grafana

We deploy both patterns side-by-side on the same EKS cluster, instrument the same set of agents with both, and show you how to choose between them — or run both simultaneously for different purposes. All infrastructure is provisioned with Terraform, and agent runtime resources are managed through AWS Controllers for Kubernetes (ACK) composed with kro (Kube Resource Orchestrator) — for details on the ACK + kro approach, see [Multi-Agent Systems for Financial Services on Amazon EKS and AgentCore](https://aws.amazon.com/blogs/industries/multi-agent-systems-for-financial-services-on-amazon-eks-and-agentcore/).

> **GitHub Repository:** [aws-samples/containers-blog-maelstrom/otel-agent-observability-patterns-blog](https://github.com/aws-samples/containers-blog-maelstrom/tree/main/otel-agent-observability-patterns-blog)

---

## Architecture Overview



![Architecture: OTEL Observability Patterns for AI Agents on Amazon EKS](images/architecture-diagram.png)

*Figure 1. Dual observability patterns on Amazon EKS. The decentralized path (orange) routes through the ADOT managed add-on to Amazon CloudWatch GenAI Observability. The centralized path (blue) routes through a self-hosted OTEL Collector to Langfuse and Amazon Managed Prometheus, with Amazon Managed Grafana for dashboards.*

The platform runs on Amazon EKS Auto Mode. Agent pods instrument with the OTEL SDK and dual-export telemetry to both observability backends simultaneously. The architecture separates into three layers:

1. **Agent layer** — Strands SDK agents instrumented with the OTEL SDK, each bound to its own AgentCore capabilities (Memory, Code Interpreter, Browser) via kro claims.
2. **Collection layer** — Two independent collectors running in parallel: the ADOT managed add-on (DaemonSet) and a self-hosted OTEL Collector (Deployment).
3. **Backend layer** — Amazon CloudWatch GenAI Observability for the decentralized pattern; Langfuse plus Amazon Managed Prometheus plus Amazon Managed Grafana for the centralized pattern.

---

## Prerequisites

- AWS account with Bedrock model access (Claude Sonnet 4.6 in `us-west-2`)
- Terraform ≥ 1.5
- `kubectl`, `helm` 3.x, AWS CLI v2
- Container runtime (Docker or Finch) for image builds

---

## Infrastructure Setup

The infrastructure setup is automated through a single script. Clone the repository and run:

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
export BEDROCK_PRIMARY_MODEL=us.anthropic.claude-sonnet-4-6-20260514
export BEDROCK_FALLBACK_MODEL=us.anthropic.claude-haiku-4-5-20260514

```

All scripts source this file automatically. When a new EKS version becomes available or a new model is released, update `config.env` and re-run the relevant script — no code changes required.

The script takes approximately 15–20 minutes and provisions:

- **EKS cluster (v1.35)** with Auto Mode, Pod Identity, and the ADOT managed add-on
- **ACK + kro EKS Capabilities** for managing AgentCore resources as Kubernetes CRs
- **Amazon Managed Prometheus** and **Amazon Managed Grafana** for the centralized metrics path
- **ArgoCD** for GitOps delivery of all workloads (agents, OTEL Collector, Langfuse, Bifrost)

After completion, the script configures your `kubectl` context and waits for all capabilities to reach the `ACTIVE` state. Here is what is running once setup completes:

| Component | What It Is | What We Use It For |
| --- | --- | --- |
| **Amazon EKS (v1.35)** | AWS-managed Kubernetes service that runs containerized workloads at scale. Auto Mode handles compute, networking, and security patching automatically. | Runs all agent pods, collectors, and observability infrastructure. Pod Identity provides zero-credential IAM. |
| **ACK + kro** | ACK (AWS Controllers for Kubernetes) provisions AWS resources via Kubernetes CRs. kro (Kube Resource Orchestrator) composes multiple ACK resources into single higher-level claims. | Declares AgentCore capabilities (Memory, Browser, CodeInterpreter) as Kubernetes-native resources without Terraform or CLI. |
| **ADOT** | AWS Distro for OpenTelemetry — an AWS-supported distribution of the OpenTelemetry Collector, deployed as a managed EKS add-on. | Collects OTEL traces and metrics from agent pods (DaemonSet on every node) and exports them to CloudWatch for the decentralized pattern. |
| **Amazon Managed Prometheus** | A fully managed, Prometheus-compatible monitoring service that scales automatically. No servers to operate. | Stores time-series metrics (agent latency, token usage, error rates) shipped by the OTEL Collector for the centralized pattern. |
| **Amazon Managed Grafana** | A fully managed Grafana service for interactive visualization and alerting. Integrates natively with AMP as a data source. | Displays real-time agent performance dashboards and fires alerts on token budget or latency thresholds. |
| **ArgoCD** | A declarative, GitOps continuous delivery tool for Kubernetes. It watches a Git repository and reconciles the cluster state to match. | Manages all workloads (agents, collectors, Langfuse, Bifrost) from the repository — a Git commit triggers a rollout. |
| **OTEL Collector** | The vendor-neutral OpenTelemetry Collector — a pipeline for receiving, processing, and exporting telemetry data. | Receives OTLP from agents, fans out traces to Langfuse and metrics to AMP. Also scrapes Bifrost's Prometheus endpoint. |
| **Langfuse** | An open-source LLM observability and analytics platform purpose-built for AI applications. Provides prompt management, evaluation, and cost tracking. | Receives agent traces via OTLP and surfaces prompt versioning, quality scoring, session tracking, cost analytics, and evaluation datasets. |
| **Bifrost** | A high-performance LLM gateway/proxy that routes model requests with adaptive load balancing, fallback, and per-request cost tracking. | Routes all agent LLM calls to Amazon Bedrock. Provides model fallback (Sonnet → Haiku), cost metrics, and OTEL trace correlation via its plugin. |

> **Note:** The Terraform configurations are at `terraform/cluster/` and `terraform/bootstrap/` if you want to inspect or customize individual resources before running the script.

### Configure Langfuse Credentials

After Langfuse boots for the first time, you need to generate API keys so the OTEL Collector can authenticate when sending traces. Follow these steps:

**Step 1:** Port-forward the Langfuse UI to your local machine:

```bash
kubectl port-forward svc/langfuse -n observability 3000:3000

```

**Step 2:** Open [http://localhost:3000](http://localhost:3000) in your browser. Create an account, then create a new project.

**Step 3:** In the Langfuse project settings, navigate to **API Keys** and generate a new key pair. You will receive a Public Key (`pk-lf-...`) and a Secret Key (`sk-lf-...`).

**Step 4:** Update the Kubernetes Secret with your real credentials:

```bash
kubectl create secret generic langfuse-api-keys \
  -n observability \
  --from-literal=LANGFUSE_PUBLIC_KEY=pk-lf-your-public-key \
  --from-literal=LANGFUSE_SECRET_KEY=sk-lf-your-secret-key \
  --dry-run=client -o yaml | kubectl apply -f -

```

**Step 5:** Restart the OTEL Collector to pick up the new credentials:

```bash
kubectl rollout restart deployment/otel-collector -n observability

```

> **Note:** Until real keys are configured, the OTEL Collector will log HTTP 401 errors when exporting to Langfuse. The decentralized pattern (CloudWatch traces via ADOT) is unaffected and flows normally regardless.

---

## Agent Instrumentation with OTEL

The observability story starts inside the agent code. The goal is simple: every meaningful action the agent takes — calling a model, invoking a tool, making a decision — should produce a **span** that both CloudWatch and Langfuse can render as part of a distributed trace.

### Dual-Export OTEL Bootstrap

When an agent pod starts, it calls `init_otel()` once. This creates a TracerProvider with two exporters running in parallel — one for each observability pattern. From that point on, every span the agent creates is automatically sent to both backends with zero additional code.

The full implementation is at `agents/shared/otel_bootstrap.py`.

```python
def init_otel(service_name: str):
    """Initialize OTEL with dual export to ADOT and self-hosted Collector."""
    provider = TracerProvider(resource=Resource.create({
        ResourceAttributes.SERVICE_NAME: service_name,
        "agent.framework": "strands-sdk",
    }))

    # Exporter 1 → ADOT (DaemonSet on same node, localhost:4317)
    #   Forwards to CloudWatch GenAI Observability
    provider.add_span_processor(BatchSpanProcessor(
        OTLPSpanExporter(endpoint="http://localhost:4317", insecure=True)
    ))

    # Exporter 2 → Self-hosted OTEL Collector (ClusterIP service)
    #   Fans out to Langfuse (traces) + AMP (metrics)
    provider.add_span_processor(BatchSpanProcessor(
        OTLPSpanExporter(
            endpoint=os.getenv("OTEL_COLLECTOR_ENDPOINT",
                              "http://otel-collector.observability:4317"),
            insecure=True,
        )
    ))

    trace.set_tracer_provider(provider)
    return trace.get_tracer(service_name)

```

### Agent Code with Semantic Spans

Each agent wraps its key operations in OTEL spans that carry LLM-specific attributes. The `@tracer.start_as_current_span` decorator opens a span when the function starts and closes it when it returns. Inside the function, you attach attributes that power the dashboards.

See `agents/research_agent/app.py`.

```python
tracer = init_otel("research-agent")

@tracer.start_as_current_span("agent.invoke")
def handle_request(user_query: str) -> str:
    span = trace.get_current_span()
    span.set_attribute("agent.name", "research-agent")
    span.set_attribute("agent.query", user_query[:200])

    response = agent(user_query)

    # Token usage — powers cost dashboards in both backends
    span.set_attribute("llm.token_count.input", response.usage.input_tokens)
    span.set_attribute("llm.token_count.output", response.usage.output_tokens)
    span.set_attribute("llm.model_id", "us.anthropic.claude-sonnet-4-6-20260514")

    return str(response)

```

The Strands SDK also auto-instruments tool calls — each tool invocation becomes a child span under `agent.invoke`, so you see the full reasoning tree without additional code.

---

## Deploying the Agents

With the infrastructure running and agent code instrumented, build the images and let ArgoCD deploy them:

```bash
./scripts/setup-agents.sh

```

ArgoCD detects the new image tags, syncs the agent Deployments, and rolls out pods into the `agents` namespace. Within a few minutes, the agents are live and serving requests. From this point on, every agent invocation produces traces that flow to both observability backends simultaneously.

Verify the agents are running:

```bash
kubectl get pods -n agents

```

### Running Queries Against the Agents

With the agents deployed, send a few queries to generate traces. Port-forward the agent service and use `curl` to invoke it:

```bash
# Port-forward the research agent to localhost
kubectl port-forward svc/research-agent -n agents 8080:8080 &

# Query 1: Simple research (triggers LLM call + web_search tool)
curl -s -X POST http://localhost:8080/invoke \
  -H "Content-Type: application/json" \
  -d '{"query": "What are the top 3 performing S&P 500 sectors this quarter?"}' | jq .

# Query 2: Multi-step analysis (multiple LLM calls + summarize tool)
curl -s -X POST http://localhost:8080/invoke \
  -H "Content-Type: application/json" \
  -d '{"query": "Compare NVIDIA and AMD stock performance over the last 6 months and summarize the key drivers."}' | jq .

# Query 3: Large context request (tests token budget tracking)
curl -s -X POST http://localhost:8080/invoke \
  -H "Content-Type: application/json" \
  -d '{"query": "Analyze the Federal Reserve June 2026 meeting minutes and extract the top 5 policy signals impacting tech stocks."}' | jq .

```

Each query triggers a full reasoning chain — LLM calls, tool invocations, and response synthesis — all captured as OTEL spans. After 30–60 seconds, these traces appear in both CloudWatch GenAI Observability and Langfuse. Let us look at how each pattern surfaces them.

---

## The Decentralized Pattern — ADOT → CloudWatch GenAI Observability

In the decentralized pattern, each agent pod exports telemetry to a local ADOT collector running on the same node. There is no centralized observability infrastructure to manage — ADOT runs as a managed DaemonSet, and all data flows directly to CloudWatch. This makes it the zero-ops option: you enable the ADOT add-on, instrument your agents, and GenAI traces appear in the CloudWatch console automatically.

The pattern is called "decentralized" because there is no shared collection point inside the cluster. Each node's ADOT instance independently ships telemetry to the AWS-managed backend, eliminating the Collector as a single point of failure. The observability pipeline scales with the cluster without any manual intervention.

### How It Works

```
┌──────────────┐       ┌──────────────────┐       ┌─────────────────────────────┐
│              │       │                  │       │      Amazon CloudWatch       │
│  Agent Pod   │       │  ADOT Collector  │       │                             │
│              │       │  (DaemonSet)     │       │  ┌───────────────────────┐  │
│  Strands SDK │       │                  │       │  │ GenAI Observability   │  │
│  + OTEL SDK  │       │                  │       │  │                       │  │
│              │       │                  │       │  │  • Model latency      │  │
│              ├──────▶│   OTLP :4317     ├──────▶│  │  • Token usage/agent  │  │
│              │       │                  │       │  │  • Cost attribution   │  │
│              │       │                  │       │  │  • Error rates/tool   │  │
│              │       │                  │       │  └───────────────────────┘  │
└──────────────┘       └──────────────────┘       └─────────────────────────────┘

     Agent               Same Node                      AWS Managed
                        (localhost)

```

### Viewing Traces in CloudWatch

When we send a request to the research agent, the full trace appears in the CloudWatch GenAI Observability console. Here is what a single invocation looks like:

```
[root] agent.invoke (research-agent) ─────────────────────── 3.2s
  ├── [span] llm.call ──────────────────────────────────── 1.2s
  │         model: claude-sonnet-4.6
  │         input_tokens: 450, output_tokens: 280
  ├── [span] tool.call (web_search) ────────────────────── 0.8s
  │         status: success
  ├── [span] llm.call ──────────────────────────────────── 0.9s
  │         model: claude-sonnet-4.6
  │         input_tokens: 620, output_tokens: 150
  └── [span] tool.call (summarize) ─────────────────────── 0.3s
            status: success

```

The GenAI console aggregates these traces across all agents and surfaces:

- **Model invocation latency** — p50/p99 per model, so you can spot degradation
- **Token usage per agent** — which agents are consuming the most tokens
- **Cost attribution** — estimated spend per agent based on model pricing
- **Error rates per tool** — which tools fail most often and for which agents

*Figure 2. CloudWatch GenAI Observability console screenshots will be added after deployment.*

---

## The Centralized Pattern — OTEL Collector → Langfuse + AMP + Grafana

In the centralized pattern, all agent pods export telemetry to a single OTEL Collector Deployment in the `observability` namespace. The Collector acts as a fan-out point: it receives OTLP signals from every agent, batches and enriches them, and routes traces to Langfuse while shipping metrics to Amazon Managed Prometheus.

This pattern is called "centralized" because a single collection point aggregates all telemetry before forwarding it to multiple backends. The tradeoff is clear: you gain richer analytics (Langfuse's prompt versioning, scoring, and session tracking), cross-agent correlation, and flexible routing — at the cost of running the Collector and Langfuse in-cluster. For teams doing active prompt iteration and quality evaluation, this investment pays for itself quickly.

The Collector also enables future extensibility: adding a new backend (for example, Datadog, Honeycomb, or an S3 sink for compliance archival) requires only a new exporter block in the Collector configuration — no agent code changes.

### How It Works

```
┌──────────────┐       ┌───────────────────────┐       ┌─────────────────────┐
│              │       │                       │       │      Langfuse       │
│  Agent Pod   │       │    OTEL Collector     │       │  (LLM Analytics)    │
│              │       │  (observability ns)   │       │                     │
│  Strands SDK │       │                       │       │  • Prompt versions  │
│  + OTEL SDK  │       │                       ├──────▶│  • Quality scoring  │
│              │       │                       │       │  • Session tracking │
│              ├──────▶│     OTLP :4317        │       │  • Cost analytics   │
│              │       │                       │       └─────────────────────┘
│              │       │                       │        (traces via OTLP/HTTP)
└──────────────┘       │                       │
                       │                       │       ┌─────────────────────┐
                       │                       │       │        AMP          │
                       │                       ├──────▶│  (Metrics Store)    │
                       │                       │       │                     │
                       └───────────────────────┘       │  • Agent throughput │
                                                       │  • Latency p50/p99 │
                        (metrics via Remote Write      │  • Error rates     │
                         with SigV4 auth)              └──────────┬──────────┘
                                                                  │ PromQL
                                                                  ▼
                                                       ┌─────────────────────┐
                                                       │  Amazon Managed     │
                                                       │  Grafana            │
                                                       │  • Dashboards       │
                                                       │  • Alerts           │
                                                       └─────────────────────┘

```

### Viewing Traces in Langfuse

The same agent invocation that appeared in CloudWatch also appears in Langfuse — but with a different lens. Because the agents use `HTTPXClientInstrumentor`, outbound calls to Bifrost carry a W3C `traceparent` header. Bifrost's OTEL plugin reads this header and creates child spans under the same trace ID, producing a unified trace tree that connects agent reasoning to the actual LLM call:

```
Trace: research-agent | 3.2s | $0.0043
├── Generation (via Bifrost): claude-sonnet-4.6 ─────────── 1.2s | 450→280 tokens | $0.0026
│     prompt_version: v2.3
│     bifrost.model_route: primary
├── Tool: web_search ──────────────────────── 0.8s | success
│     input: "S&P 500 trend July 2026"
├── Generation (via Bifrost): claude-sonnet-4.6 ─────────── 0.9s | 620→150 tokens | $0.0017
│     prompt_version: v2.3
└── Tool: summarize ───────────────────────── 0.3s | success
      output_length: 342 chars

```

Beyond individual traces, Langfuse aggregates data to answer operational questions:

- **Which prompt version performs better?** — compare quality scores across v2.2 vs. v2.3
- **Which agents cost the most?** — ranked cost per agent with daily trends
- **Are sessions degrading?** — track multi-turn conversation quality over time
- **Is this change safe to ship?** — run the evaluation dataset against a new prompt before deploying

### Viewing Metrics in Grafana

A pre-built Grafana dashboard (`gitops/addons/grafana-dashboards/agent-observability.json`) is deployed automatically via ArgoCD. It displays real-time panels for both agent and Bifrost metrics:

**Agent Metrics:**

- **Request rate** — invocations per second per agent
- **Latency percentiles** — p50/p95/p99 for end-to-end agent response time
- **Token usage** — input vs. output token rate per agent
- **Estimated cost** — dollar-per-minute spend per agent based on model pricing
- **Tool success rate** — percentage of successful tool calls with error breakdown

**Bifrost LLM Proxy Metrics:**

- **Request rate by model** — how many requests each model (Sonnet vs. Haiku) is serving
- **Model latency (p95)** — response time per model at the gateway level
- **Throttle/fallback rate** — when Sonnet hits throttle limits and traffic falls back to Haiku
- **Token throughput** — input/output tokens per second flowing through the gateway

Bifrost exposes a `/metrics` endpoint on port 9090 (enabled in the Helm values). The OTEL Collector scrapes this endpoint every 15 seconds and ships the metrics to AMP alongside the agent OTEL metrics. This gives you a unified view of both the agent reasoning layer and the LLM routing layer in one dashboard.

*Figure 3. Langfuse trace view and Grafana agent dashboard screenshots will be added after deployment.*

---

## When to Use Which Pattern

| Dimension | Decentralized (CloudWatch) | Centralized (Langfuse + AMP) |
| --- | --- | --- |
| **Setup effort** | Minimal — ADOT managed add-on + IAM | Moderate — deploy Langfuse, OTEL Collector, and AMP workspace |
| **Operational overhead** | AWS-managed; no infrastructure to run | Self-managed Langfuse (or SaaS); Collector pods in-cluster |
| **LLM-specific analytics** | CloudWatch GenAI console — model latency, tokens, and cost | Langfuse — prompt versioning, scoring, sessions, and datasets |
| **Multi-cluster visibility** | CloudWatch cross-account observability | Collector federation to a shared AMP endpoint |
| **Cost model** | Pay-per-trace ingestion (CloudWatch pricing) | AMP ingestion + Langfuse hosting (or SaaS tier) |
| **Best for** | Platform/SRE teams — "Are my agents healthy and within budget?" | ML engineering teams — "Is my prompt working well and where should I iterate?" |

Both patterns can run independently or simultaneously on the same cluster. Choose based on your team's existing tooling and operational needs — or deploy both and use each for what it does best.

---

## Cleanup

```bash
./scripts/teardown.sh

```

The teardown script deletes agent workloads first (triggering ACK resource cleanup), waits for AWS-side deletes to complete (~2 minutes), and then destroys the Terraform stacks. If an ACK resource gets stuck in the `Deleting` state, clear the finalizer:

```bash
kubectl patch <kind>/<name> -n agents \
  -p '{"metadata":{"finalizers":null}}' --type=merge

```

---

## Conclusion

Observability for AI agents is not optional — it is the operational foundation that tells you whether your agents are delivering value or burning money. The two patterns in this post give you coverage across the spectrum:

- **Decentralized (CloudWatch GenAI)** for immediate, zero-infrastructure visibility into model performance and cost.
- **Centralized (Langfuse + AMP + Grafana)** for deep prompt engineering analytics, scoring, and cross-team dashboards.

By deploying both on the same EKS cluster with Terraform-managed infrastructure, you get a production-grade setup that is reproducible, version-controlled, and extensible. Every agent invocation is traced end-to-end — from the user's request, through the reasoning chain, to the final response — with cost, latency, and quality metrics at every step.

The complete implementation is available at the [AWS Samples GitHub repository](https://github.com/aws-samples/containers-blog-maelstrom/tree/main/otel-agent-observability-patterns-blog).

---

## References

- [Amazon CloudWatch GenAI Observability](https://docs.aws.amazon.com/AmazonCloudWatch/latest/monitoring/CloudWatch-GenAI-Observability.html)
- [AWS Distro for OpenTelemetry (ADOT)](https://aws-otel.github.io/)
- [Langfuse OTEL Integration](https://langfuse.com/docs/integrations/opentelemetry)
- [Amazon Managed Prometheus](https://docs.aws.amazon.com/prometheus/)
- [Amazon Managed Grafana](https://docs.aws.amazon.com/grafana/)
- [AWS Controllers for Kubernetes (ACK)](https://aws-controllers-k8s.github.io/community/)
- [kro — Kube Resource Orchestrator](https://kro.run/)
- [EKS Auto Mode](https://docs.aws.amazon.com/eks/latest/userguide/automode.html)
- [Strands Agents SDK](https://github.com/strands-agents/sdk-python)
- [Multi-Agent Systems for Financial Services on Amazon EKS and AgentCore](https://aws.amazon.com/blogs/industries/multi-agent-systems-for-financial-services-on-amazon-eks-and-agentcore/)

