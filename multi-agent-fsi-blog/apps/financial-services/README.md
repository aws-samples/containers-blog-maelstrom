# Financial Services Multi-Agent System (Strands + AgentCore + agentgateway.dev)

A reimplementation of the [`financial-services`](../financial-services/) KAgent demo using:

- **Strands SDK** — each of the four agents runs as its own Python pod behind a small FastAPI A2A wrapper.
- **Amazon Bedrock AgentCore** — Memory (advisor client profile), Code Interpreter (dynamic portfolio/risk math), Browser (live stock quotes).
- **[agentgateway.dev](https://agentgateway.dev/docs/kubernetes/latest/)** — single data plane for every Agent→Agent and Agent→MCP call, with JWT (ServiceAccount) authentication, per-SA MCP/A2A authorization, and Jaeger tracing.

## Architecture

```
                        caller (kubectl / UI)
                                 │ POST /agents/financial-advisor
                                 ▼
┌────────────────────────────────────────────────────────────────────┐
│  Agent Gateway (agentgateway-system)                               │
│   • JWT authn (Kubernetes TokenReview)                             │
│   • MCP authz + A2A authz                                          │
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
financial-services-strands/
├── agents/
│   ├── _shared/{a2a_client.py, mcp_client.py}   # gateway-aware HTTP clients
│   ├── financial-advisor/                        # Memory + 3 delegate tools
│   ├── portfolio-analyst/                        # Code Interpreter + MCP
│   ├── risk-assessment/                          # Code Interpreter
│   └── market-data/                              # Browser + MCP fallback
├── mcp-server/                                   # FastMCP-style financial tools
├── terraform/
│   ├── modules/{memory,browser,code-interpreter}/  # Bedrock AgentCore TF modules
│   └── financial-services-components/              # root module, IAM + pod-identity
├── gitops/financial-services-stack/             # Helm chart
│   └── templates/
│       ├── terraform-resource.yaml  (wave 0)
│       ├── financial-tools-mcp.yaml (wave 1)
│       ├── agents-deployment.yaml   (wave 2)
│       ├── gateway-routes.yaml      (wave 2)
│       └── gateway-policies.yaml    (wave 2)
├── argocd/financial-services-application.yaml
└── deploy.sh                                     # builds + pushes 5 images
```

## Prerequisites

The following must already be present in the cluster (provisioned by the blog walkthrough's `platform-root` app-of-apps):

1. **EKS cluster** with Pod Identity addon.
2. **ArgoCD** + **Flux** + **Terraform controller** (`tf-runner` ServiceAccount).
3. **Agent Gateway + Gateway API CRDs** installed in `agentgateway-system` with the `agent-gateway-proxy` Gateway listening on port 8080.
4. **AWS Bedrock access** for Claude 3.5/3.7 Sonnet + AgentCore Memory/Browser/CodeInterpreter in the chosen region (default `us-west-2`).
5. **ECR repositories** for the 5 images (the deploy script creates them if missing).

## Deploy

1. Edit `gitops/financial-services-stack/values.yaml`:
   - Set `eksClusterName`, `awsRegion`, `images.registry`, and the `terraform.git` URL + branch to match your fork.
2. Build + push images:
   ```bash
   ./deploy.sh
   ```
3. Apply the ArgoCD Application:
   ```bash
   kubectl apply -f argocd/financial-services-application.yaml
   ```

Sync waves:

| Wave | Resources |
|------|-----------|
| 0 | Flux `Terraform` CR → provisions Memory/Browser/CodeInterpreter + IAM + 5 Pod Identity associations + writes `financial-services-outputs-<version>` Secret |
| 1 | `financial-tools-mcp` Service + Deployment + SA |
| 2 | 4 × agent (SA + Service + Deployment with projected SA token) + Gateway backends, routes, and authz policies |

## Verify

```bash
kubectl get terraform -n financial-services
kubectl get pods -n financial-services
kubectl get httproute -n financial-services
kubectl get agentgatewaypolicy -n financial-services
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

```bash
kubectl delete application financial-services-stack -n argocd
```

The Flux Terraform controller destroys all AWS resources on delete (`destroyResourcesOnDeletion: true`).

## Differences vs the original KAgent version

| Concern | KAgent (`../financial-services`) | Strands (this folder) |
|---|---|---|
| Orchestration | KAgent `Agent` CRDs | Strands `Agent` in Python pods |
| A2A | In-process inside KAgent | HTTP via Agent Gateway `/agents/<name>` |
| MCP | `RemoteMCPServer` CRD | HTTP via Agent Gateway `/mcp` |
| Tool data | All simulated | Browser for live quotes, Code Interpreter for math |
| Auth | None | Projected SA JWT (audience `agent-gateway`) validated via TokenReview |
| Deploy | bash `deploy.sh` | GitOps (ArgoCD + Flux Terraform) |



#####
- EKS Auto Mode
- ArgoCD Capability
- FluxCD
- Tofu Controller
- LiteLLM
- AgentGateway
- Langfuse (just mention)

Terraform IaC
Install the addons in wave 0 in ArgoCD
Agents in wave 1 in ArgoCD

