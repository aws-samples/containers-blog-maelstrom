# OTEL Agent Observability Patterns on Amazon EKS

Companion code for the AWS Containers blog post:
**"Centralized vs. Decentralized: OTEL Observability Patterns for AI Agents on Amazon EKS"**

## Quick Start

```bash
# 1. Edit config.env (region, cluster name, model preferences)
vi config.env

# 2. Provision infrastructure (EKS Auto Mode, ADOT, AMP, Grafana, ArgoCD)
./scripts/setup-infra.sh

# 3. Build and deploy agents
./scripts/setup-agents.sh

# 4. Configure Langfuse credentials (see blog post for steps)

# 5. Verify observability
./scripts/verify-observability.sh

# Teardown
./scripts/teardown.sh
```

## Prerequisites

- AWS account with Bedrock model access (Claude Sonnet 4.6, `us-west-2`)
- Terraform >= 1.5, kubectl, helm 3.x, AWS CLI v2
- Docker or Finch for image builds

## Structure

```
├── config.env              # Central configuration (edit before running)
├── Dockerfile              # Multi-agent container build
├── terraform/
│   ├── cluster/            # EKS Auto Mode, VPC, IAM, AMP, Grafana
│   └── bootstrap/          # ArgoCD, cert-manager, kro, ADOT, gp3 StorageClass
├── agents/                 # Agent source code with OTEL instrumentation
│   ├── shared/             # Dual-export OTEL bootstrap module
│   ├── research_agent/     # Financial research agent (FastAPI + tools)
│   └── data_agent/         # Data retrieval agent
├── gitops/                 # ArgoCD app-of-apps
│   ├── root/               # Root Helm chart (deploys all children)
│   └── addons/             # Individual components
│       ├── agents/         # Agent Helm chart (Deployments + Services)
│       ├── agentcore-rgds/ # kro ResourceGraphDefinitions
│       ├── bifrost/        # LLM proxy with metrics
│       ├── grafana-dashboards/  # Pre-built Grafana dashboard
│       └── langfuse/       # Langfuse credentials Secret
├── helm-values/            # Reference Helm values (documentation)
├── image-build/            # requirements.txt for container builds
└── scripts/                # Setup, teardown, verification
```

## What Gets Deployed

| Component | Description |
|-----------|-------------|
| EKS Auto Mode (v1.35) | Cluster with managed NodePools, Pod Identity |
| ADOT | Managed add-on for CloudWatch GenAI traces |
| ArgoCD | GitOps delivery of all workloads |
| cert-manager | TLS certificate management (ADOT dependency) |
| kro | Kube Resource Orchestrator for AgentCore CRs |
| OTEL Collector | Fan-out: traces to Langfuse, metrics to AMP |
| Langfuse | LLM analytics (prompt versioning, scoring, cost) |
| Bifrost | LLM proxy (model routing, fallback, metrics) |
| AMP + Grafana | Metrics store + dashboards |

## References

- [Blog Post](https://aws.amazon.com/blogs/containers/...)
- [Multi-Agent FSI Blog (ACK + kro reference)](https://aws.amazon.com/blogs/industries/multi-agent-systems-for-financial-services-on-amazon-eks-and-agentcore/)
