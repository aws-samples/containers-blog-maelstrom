# Building a Multi-Agent Financial Services Platform on EKS Auto Mode

> End-to-end walkthrough for the AWS blog. Provisions an EKS Auto Mode cluster with ArgoCD, bootstraps a full agent platform (Flux, Tofu Controller, Agent Gateway, LiteLLM), and deploys a four-agent Strands + Amazon Bedrock AgentCore financial services demo.

---

## What you build

```
                                 Client / UI
                                     │ HTTPS (JWT: SA token, audience=agent-gateway)
                                     ▼
┌────────────────────────────────────────────────────────────────────────┐
│                         Agent Gateway (agentgateway.dev)               │
│   JWT authn  │  MCP authz  │  A2A authz  │  OTLP → Jaeger              │
└───────┬─────────────────────────────────────┬──────────────────────────┘
        │ /agents/financial-advisor          │ /mcp
        ▼                                     ▼
┌────────────────────────┐         ┌──────────────────────┐
│ financial-advisor      │ A2A ──▶ │ portfolio-analyst     │── MCP ──▶ financial-tools-mcp
│  (Memory)              │ A2A ──▶ │ risk-assessment       │             (FastAPI JSON-RPC)
│                        │ A2A ──▶ │ market-data           │
└────────────────────────┘         └──────────────────────┘
        │                                   │
        │ LiteLLM (OpenAI-compatible)       │ Bedrock AgentCore
        ▼                                   ▼
┌────────────────────────┐         ┌──────────────────────┐
│  LiteLLM proxy         │ ──────▶ │  Bedrock              │
│  (cost, fallback)      │         │  Claude / AgentCore   │
└────────────────────────┘         │  Memory, CodeInterp,  │
                                   │  Browser              │
                                   └──────────────────────┘
```

**Capabilities used**

| Agent | AgentCore capability | MCP tools | A2A targets |
|---|---|---|---|
| financial-advisor | Memory (cross-session client profile) | — | portfolio-analyst, risk-assessment, market-data |
| portfolio-analyst | Code Interpreter (dynamic valuation) | `calculate_portfolio_value`, `get_stock_price` | — |
| risk-assessment | Code Interpreter (LLM-generated risk scoring) | — | — |
| market-data | Browser (live Yahoo Finance quotes) | `get_stock_price`, `get_market_trends` | — |

All LLM calls route through **LiteLLM** for per-agent token spend tracking and model fallback. All agent-to-agent and agent-to-MCP calls route through **Agent Gateway** for identity-based authz and distributed tracing.

---

## Why EKS Auto Mode

Auto Mode removes the largest chunks of ops toil for agent platforms:

- **Compute:** managed NodePools (`system`, `general-purpose`) autoscale without installing Karpenter.
- **Networking:** VPC CNI, kube-proxy, CoreDNS, and the AWS Load Balancer Controller ship preinstalled.
- **Storage:** EBS CSI driver is managed.

For the blog, this means the Terraform for the cluster is ~60 lines and all the platform-specific addons (Flux, Tofu Controller, Agent Gateway, LiteLLM, Jaeger) can be ArgoCD Applications instead of Helm charts we manage outside GitOps.

---

## Repository layout

```
multi-agent-fsi-blog/
├── terraform/
│   ├── cluster/        # EKS Auto Mode + VPC + Pod Identity + tf-runner IAM
│   └── bootstrap/      # ArgoCD + app-of-apps root Application
├── gitops/
│   ├── root/           # One Argo Application per addon (app-of-apps)
│   └── addons/         # Manifests backing those Applications
│       ├── agent-gateway-config/   (Gateway, tracing, RBAC, Jaeger)
│       └── litellm/                (values.yaml for the Helm chart)
├── apps/
│   └── financial-services/   # Strands + AgentCore + MCP financial demo
│       ├── agents/           # 4 Strands agents + _shared clients
│       ├── mcp-server/       # FastAPI JSON-RPC tools server
│       ├── terraform/        # AgentCore Memory/Browser/CodeInterp + IAM
│       ├── gitops/           # Helm chart (synced by platform-root)
│       └── deploy.sh         # builds + pushes 5 images to Docker Hub
└── scripts/
    └── bootstrap.sh    # Runs both Terraform stacks and waits for sync
```

Everything under `multi-agent-fsi-blog/` is self-contained — no dependencies on other folders in this repo.

---

## Prerequisites

- AWS account with:
  - Bedrock model access enabled for Claude 3.5/3.7 Sonnet + Claude 3.5 Haiku in your region.
  - Bedrock AgentCore access (Memory, Browser, Code Interpreter).
  - Permissions to create EKS clusters, IAM roles, VPCs, ECR repositories.
- Local tools: `aws` CLI, `terraform` ≥ 1.5, `kubectl` ≥ 1.31, `helm` ≥ 3.14, `podman` or `docker`.
- A clone of this repo (or your own fork hosting `multi-agent-fsi-blog/gitops/`) so ArgoCD can pull manifests.

---

## Step 1 — Provision the cluster

```bash
cd multi-agent-fsi-blog/terraform/cluster

terraform init
terraform apply \
  -var "aws_region=us-west-2" \
  -var "cluster_name=finops-agents"
```

What this creates (via `terraform-aws-modules/eks/aws` v20):

- A `/16` VPC with public + private subnets across 3 AZs, tagged for EKS LB discovery.
- EKS Auto Mode cluster (`cluster_compute_config.enabled = true`, node pools `system` + `general-purpose`).
- Pod Identity addon.
- IAM admin association for the Terraform caller so the next step can Helm-install ArgoCD.
- IAM role `<cluster>-tf-runner` with AgentCore + IAM + Pod-Identity + EC2-describe permissions, bound via Pod Identity to `flux-system/tf-runner` so Tofu Controller can provision Bedrock AgentCore resources once it's synced. Terraform creates the role up front; the SA itself is created by the tf-controller Helm chart when ArgoCD brings Wave 1 online.

About 15 minutes. Then:

```bash
aws eks update-kubeconfig --region us-west-2 --name finops-agents
kubectl get nodes
```

Nodes appear lazily — Auto Mode provisions them on demand when the first workloads land.

---

## Step 2 — Bootstrap ArgoCD + app-of-apps

```bash
cd multi-agent-fsi-blog/terraform/bootstrap

terraform apply \
  -var "cluster_name=finops-agents" \
  -var "gitops_repo_url=https://github.com/aws-samples/containers-blog-maelstrom" \
  -var "gitops_repo_branch=multi-agent-fsi-blog"
```

This installs the ArgoCD Helm chart and then applies one `Application` named `platform-root` that points at `multi-agent-fsi-blog/gitops/root/`. ArgoCD reads every file under that path and creates one Application per addon.

---

## Step 3 — How the platform comes up (sync waves)

`gitops/root/` uses ArgoCD sync-wave annotations to order the bring-up:

| Wave | Application | Why it runs here |
|:---:|---|---|
| −1 | `gateway-api-crds` | Gateway API CRDs must exist before any HTTPRoute |
| −1 | `agentgateway-crds` | `AgentgatewayBackend` / `AgentgatewayPolicy` CRDs |
| 0 | `flux` | Source + notification controllers (Tofu Controller depends on them) |
| 1 | `tofu-controller` | Runs Terraform-in-cluster for AgentCore resources |
| 2 | `agent-gateway` | The Agent Gateway proxy (needs CRDs + Pod Identity) |
| 2 | `agent-gateway-config` | Gateway resource, Jaeger, tracing policy, token-reviewer RBAC |
| 3 | `litellm` | OpenAI-compatible proxy in front of Bedrock |
| 4 | `financial-services` | The four Strands agents + MCP server (Helm chart at `apps/financial-services/`) |

Watch it reconcile:

```bash
kubectl get application -n argocd -w
```

Expected end state: all 7 addon Applications `Synced / Healthy`.

---

## Step 4 — LiteLLM configuration

`gitops/addons/litellm/values.yaml` defines:

- A **primary model** `finops-primary` backed by Bedrock Claude 3.7 Sonnet.
- A **fallback** chain to `claude-haiku` if the primary errors or is rate-limited.
- `prometheus` success/failure callbacks so token spend lands in your existing dashboards.
- A master API key (override with your own Secret in production).

The financial-services agents read `LITELLM_URL`, `LITELLM_MODEL`, and `LITELLM_API_KEY` at startup (see `_shared/model.py`). Strands' LiteLLM provider — or its OpenAI provider pointed at LiteLLM's `/v1` endpoint — wraps every inference in a proxy call, so each agent's token usage shows up in LiteLLM's `/spend` report.

**FinOps dashboard (quick peek):**

```bash
kubectl port-forward -n litellm svc/litellm 4000:4000 &
curl -s -H "Authorization: Bearer sk-finops-demo-master" \
  http://localhost:4000/spend/tags | jq
```

---

## Step 5 — Agent Gateway identity model

- Every agent pod mounts a **projected ServiceAccount token** with `audience: agent-gateway` at `/var/run/secrets/agent-gateway/token`.
- Agent Gateway validates the token via `TokenReview` against the Kubernetes API.
- The `sub` claim (e.g. `system:serviceaccount:financial-services:financial-advisor-sa`) becomes the principal for authz.
- Two `AgentgatewayPolicy` documents gate traffic:
  - **MCP authz** — which SAs can call which tools on `/mcp`.
  - **A2A authz** — which SAs can call which agents on `/agents/<name>`.

Only `financial-advisor-sa` is allowed to reach the three specialists; specialists cannot call each other. Negative test:

```bash
TOKEN=$(kubectl create token market-data-sa -n financial-services \
  --duration=1h --audience=agent-gateway)

curl -s -o /dev/null -w '%{http_code}\n' -X POST \
  http://agent-gateway-proxy.agentgateway-system.svc.cluster.local:8080/agents/portfolio-analyst \
  -H "Authorization: Bearer $TOKEN"
# → 403
```

---

## Step 6 — Run the end-to-end demo

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

**What happens under the hood:**

1. The advisor calls `get_client_profile()` (AgentCore Memory) to recall stored tolerance/goals.
2. It `delegate_market(...)` → Agent Gateway `/agents/market-data`. market-data uses AgentCore Browser to scrape live AAPL + GOOGL prices from finance.yahoo.com, falling back to the MCP `get_stock_price` tool if scraping fails.
3. It `delegate_portfolio(...)` → portfolio-analyst fetches prices via MCP `get_stock_price`, then asks the LLM (routed through LiteLLM) to generate Python, runs it in AgentCore **Code Interpreter**, and returns total value + per-holding weights.
4. It `delegate_risk(...)` → risk-assessment generates a scoring script, executes it in Code Interpreter, and compares the score against the client's `medium` tolerance.
5. The advisor synthesizes a recommendation and calls `save_client_profile(...)` to persist any new info via Memory.

**Expected Jaeger trace** (`kubectl port-forward -n agentgateway-system svc/jaeger 16686:16686`):

- Root `POST /agents/financial-advisor`
  - child `POST /agents/market-data` → child `POST /mcp` × 2
  - child `POST /agents/portfolio-analyst` → child `POST /mcp` × 3
  - child `POST /agents/risk-assessment`

All spans carry `agent.identity` attribute matching the caller's SA.

---

## Step 7 — FinOps view

Because every LLM call goes through LiteLLM, you get token spend + latency per request without touching agent code. Wire it up:

- **Per-agent budget:** create a LiteLLM "team" per agent SA and set a budget via the LiteLLM admin API.
- **Cost attribution:** tag requests in `_shared/model.py` with the agent name so LiteLLM's `/spend/tags` report slices by agent.
- **Jaeger + Prometheus:** Agent Gateway emits per-call latency + identity; LiteLLM emits per-call token counts + model. Join them on `trace_id` for per-request, per-model cost.

---

## Cleanup

```bash
# Strands demo
kubectl delete application financial-services -n argocd
# Platform addons
kubectl delete application platform-root -n argocd

cd multi-agent-fsi-blog/terraform/bootstrap && terraform destroy -auto-approve
cd ../cluster && terraform destroy -auto-approve
```

Tofu Controller deletes the AgentCore resources (Memory, Browser, Code Interpreter) because the Terraform CR has `destroyResourcesOnDeletion: true`.

---

## What to tell readers

**Trade-offs worth calling out in the post:**

- **LiteLLM hop** adds ~30–80 ms per inference; worth it for unified cost tracking and fallback routing, but some readers will want Bedrock-direct. `LITELLM_URL=""` in the agent env disables the proxy — `_shared/model.py` falls back to Strands' default provider.
- **Agent Gateway ≠ Google A2A spec.** This walkthrough uses plain JSON over HTTP to `/agents/<name>`. If you need A2A spec compliance, wrap the agent's FastAPI `POST /` with the task/artifact envelope.
- **Browser reliability.** Yahoo Finance layout drifts. The market-data agent always falls back to MCP deterministic prices — fine for a demo, but real production needs a stable data provider.
- **Pod Identity requirement.** Auto Mode supports Pod Identity out of the box, but the addon must be enabled (Terraform does this). IRSA also works but costs a second IAM role and an OIDC hop.

**Where to go next**

- Add Keycloak in front of Agent Gateway for external-facing auth instead of K8s SA tokens — OIDC discovery + bearer-token rewrites replace the Kubernetes TokenReview path.
- Add a second specialist (e.g. `compliance-agent`) using the same template to show the platform scales.
- Replace the deterministic MCP tools with a real data provider (Bloomberg, Alpaca, etc.) and benchmark throughput.
