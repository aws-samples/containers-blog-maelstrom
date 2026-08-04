# Financial Services Multi-Agent System (Strands + AgentCore + agentgateway.dev)

A reimplementation of the [`financial-services`](../financial-services/) KAgent demo using:

- **Strands SDK** — each of the four agents runs as its own Python pod behind a small FastAPI A2A wrapper.
- **Amazon Bedrock AgentCore** — Memory (advisor client profile), Code Interpreter (dynamic portfolio/risk math), Browser (live stock quotes).
- **[agentgateway.dev](https://agentgateway.dev/docs/kubernetes/latest/)** — single data plane for every Agent→Agent and Agent→MCP call, with JWT (ServiceAccount) authentication, per-SA MCP/A2A authorization, and Jaeger tracing.
- **AWS Controllers for Kubernetes (ACK) + kro** — per-agent AgentCore resources + IAM role + Pod Identity association are declared as Kubernetes CRs (composite kro claims that expand to ACK resources) and reconciled directly against the AWS API. No Flux, no Terraform-in-cluster.

## Architecture

```
                        caller (kubectl / UI)
                                 │ POST /agents/financial-advisor
                                 │ Authorization: Bearer <K8s SA JWT>
                                 ▼
┌────────────────────────────────────────────────────────────────────┐
│  Agent Gateway (agentgateway-system)                               │
│   • JWT authn (EKS OIDC via jwtAuthentication policy)              │
│   • MCP authz + A2A authz (CEL on jwt.sub)                         │
│   • OTLP → Jaeger                                                  │
└──┬─────────────────────────────────────────────────────────────────┘
   │ /agents/<name>                        /mcp
   ▼                                       ▼
┌──────────────────┐  A2A via gateway  ┌──────────────────────┐
│ financial-       │ ───────────────▶  │ portfolio-analyst    │◀── MCP
│ advisor          │ ───────────────▶  │ risk-assessment      │   (get_stock_price,
│ (Memory)         │ ───────────────▶  │ market-data          │    calculate_portfolio_value,
└──────────────────┘                   │ (Code Int. / Browser)│    get_market_trends)
                                       └──────────┬───────────┘
                                                  │ MCP via gateway
                                                  ▼
                                       ┌──────────────────────┐
                                       │ financial-tools-mcp  │
                                       │ (FastAPI JSON-RPC)   │
                                       └──────────────────────┘
```

## Folder layout

```
financial-services/
├── agents/
│   ├── _shared/{a2a_client.py, mcp_client.py, model.py}  # gateway-aware clients
│   ├── financial-advisor/                # Memory + 3 delegate tools
│   ├── portfolio-analyst/                # Code Interpreter + MCP
│   ├── risk-assessment/                  # Code Interpreter
│   └── market-data/                      # Browser + MCP fallback
├── mcp-server/                           # FastMCP-style financial tools
├── gitops/financial-services-stack/      # Helm chart (synced by platform-root)
│   └── templates/
│       ├── agentcore-resources.yaml      # Per-agent kro claims + ACK resources:
│       │                                   Memory / Browser / CodeInterpreter
│       │                                   + Role + PodIdentityAssociation
│       ├── financial-tools-mcp.yaml      # Single MCP server Deployment + Service
│       ├── litellm-api-key.yaml          # Secret bridging to the LiteLLM proxy
│       ├── agents-deployment.yaml        # 4× agent SA + Service + Deployment
│       ├── gateway-routes.yaml           # AgentgatewayBackend + HTTPRoute per agent
│       └── gateway-policies.yaml         # JWT authn + per-route A2A/MCP authz
├── terraform/                            # Break-glass only — the chart
│   │                                       does NOT reference this anymore.
│   ├── modules/{memory,browser,code-interpreter}/
│   └── financial-services-components/    # Single-agent local `terraform apply`
│                                           path, documented as the break-glass
│                                           fallback in the top-level README.
└── deploy.sh                             # finch build + push of 5 images
```

## Prerequisites

The following must already be present in the cluster (provisioned by the blog walkthrough's `platform-root` app-of-apps in `../../gitops/root/`):

1. **EKS cluster** with Auto Mode + Pod Identity.
2. **ArgoCD**.
3. **ACK + kro EKS Capabilities** — the ACK Capability installs the `bedrockagentcorecontrol`, `iam`, and `eks` service controllers; the kro Capability installs kro. Both are created by `terraform/cluster/ack_capability_iam.tf` with their IAM roles. The AgentCore composite kinds are served by the RGDs in `gitops/addons/agentcore-rgds/` (synced via `gitops/root/templates/13-agentcore-rgds.yaml`).
4. **Agent Gateway + Gateway API CRDs** installed in `agentgateway-system` with the `agent-gateway-proxy` Gateway listening on port 8080.
5. **AWS Bedrock model access** for Claude Sonnet 4.6 + Claude Haiku 4.5 in the chosen region (default `us-west-2`).
6. **Docker Hub prebuilt images** under `sriram430/financial-services-agents` (or rebuild with `./deploy.sh` and override `images.registry` in `values.yaml`).

## Deploy

Normally you don't deploy this chart directly — `platform-root` syncs it as wave 4. To iterate on just the financial-services chart:

1. Push your edits to the branch `gitops_repo_url`/`gitops_repo_branch` point at.
2. `kubectl -n argocd annotate application financial-services argocd.argoproj.io/refresh=hard --overwrite`
3. Watch it reconcile: `kubectl get application financial-services -n argocd -w`

To rebuild an agent image:

```bash
./deploy.sh   # builds + pushes all 5 images to docker.io/sriram430/financial-services-agents
# Bump the corresponding tag in gitops/financial-services-stack/values.yaml
# and let ArgoCD sync.
```

Sync order (inside this chart):

| Wave | Resources |
|------|-----------|
| 0 | Namespace + per-agent ACK resources + kro claims (Memory / Browser / CodeInterpreter / Role / PodIdentityAssociation). Each AgentCore claim's RGD writes the Secret (`fs-<agent>-<kind>-outputs`) from the ACK resource's `status.id` as soon as it is set. |
| 1 | `financial-tools-mcp` Service + Deployment + SA, `litellm-api-key` Secret. |
| 2 | 4× agent (SA + Service + Deployment with projected SA token), gateway backends + routes, authz policies. |

## Verify

```bash
# ACK / kro side
kubectl get agentcorememories,agentcorebrowsers,agentcorecodeinterpreters -n financial-services
kubectl get memories,browsers,codeinterpreters.bedrockagentcorecontrol.services.k8s.aws -n financial-services
kubectl get roles.iam.services.k8s.aws,podidentityassociations.eks.services.k8s.aws -n financial-services
kubectl get secret -n financial-services | grep -E 'fs-.*-(memory|browser|code-interpreter)-outputs'

# K8s workloads
kubectl get pods -n financial-services
kubectl get httproute -n financial-services
kubectl get agentgatewaypolicy -A
```

Smoke test through the gateway:

```bash
TOKEN=$(kubectl create token financial-advisor-sa -n financial-services \
  --duration=1h --audience=agent-gateway)

kubectl run curl --rm -it --image=curlimages/curl --restart=Never -- \
  curl -s -X POST \
    http://agent-gateway-proxy.agentgateway-system.svc.cluster.local:8080/agents/financial-advisor \
    -H "Authorization: Bearer $TOKEN" \
    -H "Content-Type: application/json" \
    -d '{"task":"I have 100 AAPL and 50 GOOGL. Is my portfolio balanced for medium risk?"}'
```

Expected Jaeger trace (service `agent-gateway`):

- `POST /agents/financial-advisor`
  - `POST /agents/market-data` → `POST /mcp` (`get_stock_price` × 2)
  - `POST /agents/portfolio-analyst` → `POST /mcp` (`get_stock_price` × 2, `calculate_portfolio_value`)
  - `POST /agents/risk-assessment` (no MCP hop; Code Interpreter is called from the agent directly, outside the gateway)

All spans are tagged with `x-agent-identity` matching the caller's ServiceAccount.

### Negative authz test

```bash
TOKEN=$(kubectl create token market-data-sa -n financial-services \
  --duration=1h --audience=agent-gateway)

# Should return 403 — market-data-sa is not allowed to call portfolio-analyst.
curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  http://agent-gateway-proxy.agentgateway-system.svc.cluster.local:8080/agents/portfolio-analyst \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"task":"hello"}'
```

## Capability matrix

| Agent | AgentCore | MCP tools | A2A targets |
|---|---|---|---|
| financial-advisor | Memory | — | portfolio-analyst, risk-assessment, market-data |
| portfolio-analyst | Code Interpreter | `calculate_portfolio_value`, `get_stock_price` | — |
| risk-assessment | Code Interpreter | — | — |
| market-data | Browser (fallback: MCP) | `get_stock_price`, `get_market_trends` | — |

## Cleanup

Normally you delete `platform-root` from ArgoCD and everything cascades. If you only want to tear down financial-services:

```bash
kubectl delete application financial-services -n argocd
# Wait for ACK resources to finish AWS-side deletes (~2 min).
kubectl get memories,browsers,codeinterpreters.bedrockagentcorecontrol.services.k8s.aws -n financial-services -w
```

If an ACK resource gets stuck in `Deleting` because the AWS resource is already gone, clear the finalizer:

```bash
kubectl patch <kind>/<name> -n financial-services \
  -p '{"metadata":{"finalizers":null}}' --type=merge
```

## Differences vs the original KAgent version

| Concern | KAgent (`../financial-services`) | Strands + ACK/kro (this folder) |
|---|---|---|
| Orchestration | KAgent `Agent` CRDs | Strands `Agent` in Python pods |
| A2A | In-process inside KAgent | HTTP via Agent Gateway `/agents/<name>` |
| MCP | `RemoteMCPServer` CRD | HTTP via Agent Gateway `/mcp` |
| Tool data | All simulated | Browser for live quotes, Code Interpreter for math |
| Auth | None | Projected SA JWT (audience `agent-gateway`) validated via EKS OIDC |
| AgentCore provisioning | n/a | kro composite claims per agent expanding to ACK resources, reconciled by ACK controllers |
| Deploy | bash `deploy.sh` | GitOps (ArgoCD) |
