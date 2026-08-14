# OTEL Agent Observability Patterns on Amazon EKS

Companion code for the AWS Containers blog post:
**"Decentralized vs. Centralized: Observability Patterns for AI Agents on Amazon EKS with Bifrost and Langfuse"**

## Quick Start

```bash
# 1. Edit config.env (region, cluster name, model preferences)
vi config.env

# 2. Provision infrastructure (EKS, ArgoCD, Langfuse, Bifrost — fully automated)
./scripts/setup-infra.sh

# 3. Build and deploy agents
./scripts/setup-agents.sh

# 4. Verify observability
./scripts/verify-observability.sh

# Teardown
./scripts/teardown.sh
```

## Prerequisites

- AWS account with Bedrock model access (Claude Sonnet 5 in `us-west-2`)
- Terraform >= 1.5, kubectl, helm 3.x, AWS CLI v2
- Docker or Finch for image builds

## Structure

```
├── config.env              # Central configuration (edit before running)
├── Dockerfile              # Multi-agent container build
├── terraform/
│   ├── cluster/            # EKS Auto Mode, VPC, IAM (Bedrock + Pod Identity)
│   └── bootstrap/          # ArgoCD, kro, gp3 StorageClass
├── agents/                 # Agent source code
│   ├── shared/             # Pattern-aware OTEL bootstrap module
│   ├── research_agent/     # Financial research agent (FastAPI + tools)
│   └── data_agent/         # Data retrieval agent
├── gitops/                 # ArgoCD app-of-apps
│   ├── root/               # Root Helm chart (deploys all children)
│   └── addons/             # Individual components
│       ├── agents/         # Agent Helm chart (Deployments + Services)
│       ├── agentcore-rgds/ # kro ResourceGraphDefinitions
│       ├── bifrost/        # LLM gateway (seed job + Helm values)
│       └── langfuse/       # Langfuse credentials Secret
├── helm-values/            # Reference Helm values (documentation)
├── image-build/            # requirements.txt for container builds
└── scripts/                # Setup, teardown, verification, Langfuse key gen
```

## What Gets Deployed

| Component | Description |
|-----------|-------------|
| EKS Auto Mode (v1.35) | Cluster with Pod Identity, auto-scaling compute |
| ArgoCD | GitOps delivery of all workloads |
| kro | Kube Resource Orchestrator for AgentCore CRs |
| Bifrost | LLM gateway — routes all agent calls to Bedrock, emits correlated OTEL spans |
| Langfuse | Single observability backend — traces, cost, token usage, prompt analytics |
| OTEL Collector | Pattern 2 only — aggregates telemetry before forwarding to Langfuse |

## Observability Patterns

Both patterns use Bifrost as the LLM gateway and Langfuse as the destination.

- **Pattern 1 (Decentralized):** Strands SDK auto-instruments. Each agent exports directly to Langfuse. No shared collector.
- **Pattern 2 (Centralized):** OTEL SDK with explicit spans. All telemetry flows through a shared OTEL Collector to Langfuse.

Switch between patterns by changing environment variables on the agent pods — no code changes needed.

## References

- [Blog Post](https://aws.amazon.com/blogs/containers/...)
- [Multi-Agent FSI Blog (ACK + kro reference)](https://aws.amazon.com/blogs/industries/multi-agent-systems-for-financial-services-on-amazon-eks-and-agentcore/)
- [Langfuse OTEL Integration](https://langfuse.com/docs/integrations/opentelemetry)
- [Bifrost LLM Gateway](https://github.com/maximhq/bifrost)
