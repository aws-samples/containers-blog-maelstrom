# Building a Multi-Agent Financial Services Platform on EKS Auto Mode

A turn-key, GitOps-driven reference architecture for a production-shaped **multi-agent AI platform** on Amazon EKS Auto Mode. Four Strands agents coordinate through **Agent Gateway** (with real JWT authentication and per-principal authorization), use **Amazon Bedrock AgentCore** for Memory, Browser, and Code Interpreter, and route every LLM call through **LiteLLM** for spend tracking and fallback routing.

One `./scripts/bootstrap.sh` runs the whole thing.

---

## Architecture at a glance

```
                                 Client / Caller
                                        │ POST /agents/financial-advisor
                                        │ Authorization: Bearer <K8s SA JWT>
                                        ▼
┌────────────────────────────────────────────────────────────────────────┐
│                     Agent Gateway (agentgateway.dev)                   │
│   JWT authn (EKS OIDC)  ·  MCP authz  ·  A2A authz  ·  OTLP → Jaeger   │
└───────┬─────────────────────────────────────┬──────────────────────────┘
        │ /agents/<name>                      │ /mcp
        ▼                                     ▼
┌────────────────────────┐         ┌──────────────────────┐
│ financial-advisor      │ A2A ──▶ │ portfolio-analyst    │── MCP ──▶ financial-tools-mcp
│  (Memory)              │ A2A ──▶ │ risk-assessment      │             (FastAPI JSON-RPC)
│                        │ A2A ──▶ │ market-data          │
└───────────┬────────────┘         └───────────┬──────────┘
            │                                  │
            │   LiteLLM (OpenAI-compatible)    │  Bedrock AgentCore
            ▼                                  ▼
┌────────────────────────┐         ┌──────────────────────┐
│  LiteLLM proxy         │ ──────▶ │  Bedrock              │
│  (cost, fallback, SLA) │         │  Claude / AgentCore   │
└────────────────────────┘         │  Memory, CodeInterp,  │
                                   │  Browser              │
                                   └──────────────────────┘
```

**Who calls whom:**

| Agent | AgentCore capability | MCP tools | A2A targets |
|---|---|---|---|
| financial-advisor | Memory (cross-session client profile) | — | portfolio-analyst, risk-assessment, market-data |
| portfolio-analyst | Code Interpreter (dynamic valuation) | `calculate_portfolio_value`, `get_stock_price` | — |
| risk-assessment | Code Interpreter (LLM-generated risk scoring) | — | — |
| market-data | Browser (live Yahoo Finance quotes) | `get_stock_price`, `get_market_trends` | — |

Every inter-agent hop is authenticated with a Kubernetes ServiceAccount JWT, authorized at the gateway on the `sub` claim, and traced into Jaeger.

---

## Why EKS Auto Mode

Auto Mode removes the largest chunks of ops toil for agent platforms:

- **Compute**: managed NodePools (`system`, `general-purpose`) autoscale without installing Karpenter.
- **Networking**: VPC CNI, kube-proxy, CoreDNS, and the AWS Load Balancer Controller ship preinstalled.
- **Storage**: the EBS CSI driver is managed (this walkthrough creates a default `StorageClass` that points at it).
- **Identity**: EKS Pod Identity is in the data plane — no separate addon to manage.

For the blog, that means the cluster Terraform is ~100 lines and every platform component lands via ArgoCD instead of a bespoke set of Helm releases.

---

## Repository layout

```
multi-agent-fsi-blog/
├── scripts/bootstrap.sh        # one-command end-to-end bring-up
├── terraform/
│   ├── cluster/                # EKS Auto Mode + VPC + tf-runner IAM
│   └── bootstrap/              # ArgoCD install + platform-root Application
│                                 (reads cluster OIDC issuer + JWKS,
│                                  plumbs into ArgoCD helm parameters)
├── gitops/
│   ├── root/                   # Helm chart. One Argo Application per addon.
│   │                             Sync waves order the bring-up end-to-end.
│   └── addons/
│       ├── agent-gateway-config/   Gateway, Jaeger, tracing policy, RBAC
│       ├── auto-mode-defaults/     default StorageClass + IngressClass
│       └── litellm/                values.yaml for the BerriAI Helm chart
└── apps/
    └── financial-services/
        ├── agents/             # 4 Strands agents (+_shared clients)
        ├── mcp-server/         # FastAPI JSON-RPC tools server
        ├── terraform/          # AgentCore Memory/Browser/CodeInterpreter
        ├── gitops/             # Helm chart (synced by platform-root)
        └── deploy.sh           # finch build+push 5 images to Docker Hub
```

Everything under `multi-agent-fsi-blog/` is self-contained — no dependencies on other folders in this repo.

---

## Prerequisites

**AWS account**
- Bedrock model access enabled in your region for **Claude Sonnet 4.6** and **Claude Haiku 4.5** (or equivalents — update `gitops/addons/litellm/values.yaml` if you pick different ids).
- Bedrock AgentCore access (Memory, Browser, Code Interpreter — `us-west-2` and `us-east-1` are the best-supported regions today).
- Permissions to create VPCs, EKS clusters, IAM roles, and EC2 resources.

**Local tools**
- `aws` CLI configured with credentials that can `eks:CreateCluster` etc.
- `terraform` ≥ 1.5, `kubectl` ≥ 1.31, `helm` ≥ 3.14, `jq`.
- `finch` (or any OCI builder) if you want to rebuild the agent images. Prebuilt images are on Docker Hub under `sriram430/financial-services-agents`.

**A git clone**
- Just clone this repo. The default `gitops_repo_url` + `gitops_repo_branch` point here. No fork needed to run the walkthrough.

---

## Quick start — one command

```bash
git clone https://github.com/aws-samples/containers-blog-maelstrom
cd containers-blog-maelstrom/multi-agent-fsi-blog
./scripts/bootstrap.sh
```

That kicks off five phases (about 20 minutes end-to-end, most of it EKS cluster creation):

1. `terraform apply` on `terraform/cluster/` — VPC + EKS Auto Mode cluster + IAM role for the Crossplane AWS providers (bound via Pod Identity to `crossplane-system/crossplane-aws-provider-sa`).
2. `aws eks update-kubeconfig` — so you can talk to the cluster.
3. `terraform apply` on `terraform/bootstrap/` — installs ArgoCD via Helm, reads the cluster's OIDC issuer + JWKS, and plumbs both into the `platform-root` ArgoCD Application via `helm.parameters` (see [Identity wiring](#identity-wiring-the-interesting-part) below).
4. Waits for every addon Application to reach `Synced / Healthy` — Gateway API + agentgateway CRDs, Auto Mode defaults, Crossplane core, Upbound AWS providers, Agent Gateway + config, LiteLLM, and the financial-services chart.
5. Waits on each Crossplane managed resource (`Memory`, `Browser`, `CodeInterpreter`, `Role`, `RolePolicy`, `PodIdentityAssociation`) to reach `Ready=True`, then rolls the agent Deployments so they pick up the newly-published connection Secrets.

Environment overrides (optional):

```bash
AWS_REGION=us-west-2 \
CLUSTER_NAME=finops-agents \
GITOPS_REPO_URL=https://github.com/<your-fork>/containers-blog-maelstrom \
./scripts/bootstrap.sh
```

### Measured wall-clock from a clean account

| Phase | Time | What happens |
|---|---|---|
| `terraform apply` cluster stack | ~15 min | VPC + subnets + NAT + EKS Auto Mode control plane + IAM for Crossplane providers |
| `terraform apply` bootstrap stack | ~2 min | ArgoCD Helm release + platform-root Application |
| ArgoCD addon reconcile (waves -1 → 3) | ~6 min | CRDs, Crossplane core, Upbound AWS providers, Agent Gateway, LiteLLM |
| Crossplane provisions AgentCore | ~3-5 min | Per-agent Memory / Browser / CodeInterpreter / IAM / Pod Identity |
| Agent pods ready + first query | ~1 min | MCP server, 4 Strands agents, Gateway policies |
| **Total cold start** | **~30 min** | fresh AWS account → working multi-agent platform |

---

## Sync waves — how ArgoCD times the rollout

```
platform-root (Application) ── orchestrates ──▶

Wave │ Application          │ Why
─────┼──────────────────────┼─────────────────────────────────────────
 -1  │ gateway-api-crds     │ HTTPRoute CRD must exist before any route
 -1  │ agentgateway-crds    │ AgentgatewayBackend / AgentgatewayPolicy CRDs
  0  │ auto-mode-defaults   │ default StorageClass + IngressClass for Auto Mode
  0  │ crossplane-core      │ Crossplane controller + core CRDs
  1  │ crossplane-providers │ Upbound provider-family-aws + bedrockagentcore +
      │                      │   iam + eks providers; ProviderConfig (IRSA/Pod
      │                      │   Identity on crossplane-aws-provider-sa)
  2  │ agent-gateway        │ The proxy itself (needs Gateway CRDs)
  2  │ agent-gateway-config │ Gateway resource, Jaeger, tracing policy, RBAC
  3  │ litellm              │ OpenAI-compatible proxy in front of Bedrock
  4  │ financial-services   │ Per-agent Crossplane MRs + MCP server + agents
```

**Inside `financial-services`** (rendered per entry in `.Values.agents`):

```
Every agent gets:
  Role.iam.aws.upbound.io                       (IAM role for the pod)
  RolePolicy.iam.aws.upbound.io                 (inline bedrock:Invoke* policy)
  PodIdentityAssociation.eks.aws.upbound.io     (binds <agent>-sa to the role)

Plus per agentcore.* toggle:
  Memory.bedrockagentcore.aws.upbound.io        (when memory = true)
  Browser.bedrockagentcore.aws.upbound.io       (when browser = true)
  CodeInterpreter.bedrockagentcore.aws.upbound.io   (when codeInterpreter = true)

Each AgentCore MR publishes its `id` to a connection Secret:
  fs-<agent>-memory-outputs             ← consumed as MEMORY_ID
  fs-<agent>-browser-outputs            ← consumed as BROWSER_ID
  fs-<agent>-code-interpreter-outputs   ← consumed as CODE_INTERPRETER_ID

Plus the K8s pieces:
  4× agent Deployment + SA + Service
  1× financial-tools-mcp Deployment + SA + Service
  5× AgentgatewayBackend + HTTPRoute
  5× AgentgatewayPolicy (1 JWT authn + A2A/MCP authz derived from agents[].role+.tools)
```

Adding a new specialist is appending one entry to `.Values.agents` — Crossplane MRs, Gateway routes, authz policies, and the agent Deployment all fan out from that single declaration:

```yaml
agents:
  - name: compliance-check
    role: specialist
    image: { repository: financial-services-agents, tag: compliance-v1 }
    agentcore:
      memory: false
      browser: false
      codeInterpreter: true
    tools: []
```

Watch it happen:

```bash
kubectl get application -n argocd -w
kubectl get memories,browsers,codeinterpreters,roles,rolepolicies,podidentityassociations \
  -n financial-services -w
```

Expected end state: every Application `Synced / Healthy`, every Crossplane MR `READY=True SYNCED=True`.

### If an agent's Crossplane MR stalls

Unlike the Flux/Terraform-controller approach this used to run on, Crossplane MRs have conventional K8s failure modes — `kubectl describe <kind> <name>` surfaces the last AWS API error on the `Synced` condition. Common issues:

- **Name collision from a previous aborted run.** Delete the orphan AgentCore resource in AWS (or import it into the MR via `crossplane.io/external-name`), then let the MR reconcile.
- **Provider not Healthy yet.** `kubectl get provider.pkg.crossplane.io` — if any provider is `INSTALLED=False` or `HEALTHY=False`, the MR will sit in `Synced=False`. Usually resolves within ~2 min of the `crossplane-providers` Application going Synced; if not, check `kubectl describe provider <name>`.
- **Pod Identity not propagated.** If the provider Deployment's SA isn't bound to the IAM role yet, AWS calls 403. `aws eks describe-pod-identity-association` and confirm `crossplane-system/crossplane-aws-provider-sa` is associated with the role from `terraform/cluster` outputs.

**Blast radius is per-MR.** An unhealthy `Memory` for `financial-advisor` doesn't affect `portfolio-analyst`'s `CodeInterpreter` — each MR reconciles independently, writes its own connection Secret, and feeds exactly one agent.

---

## Identity wiring (the interesting part)

The Agent Gateway's JWT authentication requires the cluster's OIDC issuer URL and the matching JWKS. Both are produced by EKS at cluster-creation time. Rather than make the reader copy values around, the Terraform reads them directly:

```hcl
# terraform/bootstrap/main.tf
locals {
  oidc_issuer = data.aws_eks_cluster.cluster.identity[0].oidc[0].issuer
}

data "http" "eks_jwks" {
  url = "${local.oidc_issuer}/keys"
}

resource "kubectl_manifest" "root_app" {
  yaml_body = yamlencode({
    # ...
    spec = {
      source = {
        helm = {
          parameters = [
            # ... existing parameters ...
            { name = "eks.oidcIssuer", value = local.oidc_issuer },
            { name = "eks.jwksJson",   value = data.http.eks_jwks.response_body, forceString = true },
          ]
        }
      }
    }
  })
}
```

Those parameters cascade through the app-of-apps chain until they reach `apps/financial-services/gitops/financial-services-stack/templates/gateway-policies.yaml`, which renders the actual `AgentgatewayPolicy`. No manual values edits.

**JWKS rotation.** EKS rotates its signing key roughly annually. Rotation is: re-run `terraform apply` on `terraform/bootstrap/`. The `data "http"` call picks up the new JWKS, ArgoCD re-renders the policy, traffic keeps flowing. A more automated path is to swap `jwks.inline` for `jwks.remote` pointed at an in-cluster proxy or ExternalName Service — left as a follow-up.

---

## Policy model: authn + authz in practice

After bootstrap, five `AgentgatewayPolicy` objects are live:

```bash
kubectl get agentgatewaypolicy -A
#
# NAMESPACE             NAME                            ATTACHED
# agentgateway-system   financial-services-jwt-authn    True
# agentgateway-system   tracing-policy                  True
# financial-services    financial-tools-mcp-authz       True
# financial-services    market-data-a2a-authz           True
# financial-services    portfolio-analyst-a2a-authz     True
# financial-services    risk-assessment-a2a-authz       True
```

**Authentication (Gateway-level, `mode: Strict`)**
- Every request must carry a JWT signed by the EKS OIDC issuer with audience `agent-gateway`.
- Requests missing a token, presenting a bad signature, or using the wrong audience are rejected with **401**.

**Authorization (per HTTPRoute, CEL expressions on JWT claims)**
- `/agents/portfolio-analyst`, `/agents/risk-assessment`, `/agents/market-data` → allow only `jwt.sub == "system:serviceaccount:financial-services:financial-advisor-sa"`.
- `/mcp` → allow the three specialist SAs; deny the advisor SA (the advisor delegates, never calls MCP directly).
- `/agents/financial-advisor` has no authz policy — it's the public entry point, still gated by Gateway-level authn.

The seven one-liner tests that prove this works end-to-end:

```bash
kubectl port-forward -n agentgateway-system svc/agent-gateway-proxy 8080:8080 &

ADVISOR=$(kubectl create token financial-advisor-sa -n financial-services \
  --duration=1h --audience=agent-gateway)
MARKET=$(kubectl create token market-data-sa -n financial-services \
  --duration=1h --audience=agent-gateway)
WRONG_AUD=$(kubectl create token financial-advisor-sa -n financial-services \
  --duration=1h --audience=wrong-aud)

status() { curl -sS -o /dev/null -w "$1 -> HTTP %{http_code}\n" -m 30 "${@:2}"; }

# authn
status "no auth header   " -X POST http://localhost:8080/agents/financial-advisor -d '{"task":"x"}' -H "Content-Type: application/json"
status "bad bearer       " -X POST http://localhost:8080/agents/financial-advisor -d '{"task":"x"}' -H "Content-Type: application/json" -H "Authorization: Bearer nope"
status "wrong audience   " -X POST http://localhost:8080/agents/financial-advisor -d '{"task":"x"}' -H "Content-Type: application/json" -H "Authorization: Bearer $WRONG_AUD"

# authz (A2A)
status "advisor -> pa    " -X POST http://localhost:8080/agents/portfolio-analyst -d '{"task":"ping"}' -H "Content-Type: application/json" -H "Authorization: Bearer $ADVISOR"
status "market  -> pa    " -X POST http://localhost:8080/agents/portfolio-analyst -d '{"task":"ping"}' -H "Content-Type: application/json" -H "Authorization: Bearer $MARKET"

# authz (MCP)
status "advisor -> /mcp  " -X POST http://localhost:8080/mcp -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' -H "Content-Type: application/json" -H "Authorization: Bearer $ADVISOR"
status "market  -> /mcp  " -X POST http://localhost:8080/mcp -d '{"jsonrpc":"2.0","id":1,"method":"tools/list"}' -H "Content-Type: application/json" -H "Authorization: Bearer $MARKET"
```

Expected output:

```
no auth header    -> HTTP 401
bad bearer        -> HTTP 401
wrong audience    -> HTTP 401
advisor -> pa     -> HTTP 200
market  -> pa     -> HTTP 403
advisor -> /mcp   -> HTTP 403
market  -> /mcp   -> HTTP 200
```

---

## The demo query

```bash
kubectl port-forward -n agentgateway-system svc/agent-gateway-proxy 8080:8080 &

TOKEN=$(kubectl create token financial-advisor-sa -n financial-services \
  --duration=1h --audience=agent-gateway)

curl -sS -X POST http://localhost:8080/agents/financial-advisor \
  -H "Authorization: Bearer $TOKEN" \
  -H "Content-Type: application/json" \
  -d '{"task":"I have 100 AAPL and 50 GOOGL. Is my portfolio balanced for medium risk?"}' \
  | jq -r .result
```

What happens:

1. Advisor calls `get_client_profile()` (AgentCore **Memory**) to recall prior tolerance / goals.
2. Delegates to **market-data** over A2A; that agent uses AgentCore **Browser** to fetch live AAPL + GOOGL quotes from finance.yahoo.com, falling back to MCP `get_stock_price` if scraping fails.
3. Delegates to **portfolio-analyst**; it pulls prices via MCP, asks the LLM (routed through LiteLLM) to generate Python for valuation, and executes it in AgentCore **Code Interpreter**. Returns total value + per-holding weights.
4. Delegates to **risk-assessment**; it generates scoring code, runs it in Code Interpreter, and scores against the client's `medium` tolerance.
5. Advisor synthesizes a recommendation and `save_client_profile(...)` persists any new info to Memory for next session.

In Jaeger (`kubectl port-forward -n agentgateway-system svc/jaeger 16686:16686`), the full span tree with `x-agent-identity` on every edge shows up under service `agent-gateway`.

---

## FinOps view

Because every LLM call goes through LiteLLM, per-agent token spend and latency land in the proxy's Postgres backend:

```bash
kubectl port-forward -n litellm svc/litellm 4000:4000 &
curl -s -H "Authorization: Bearer sk-finops-demo-master" \
  http://localhost:4000/spend/tags | jq
```

Wire it up further:

- **Per-agent budget**: create a LiteLLM "team" per agent SA and set a budget via the LiteLLM admin API.
- **Cost attribution**: tag outbound LiteLLM calls in `_shared/model.py` with the agent name so `/spend/tags` slices cleanly.
- **Join with traces**: Agent Gateway emits per-call latency + identity; LiteLLM emits per-call tokens + model. Joining on `trace_id` gives per-request, per-model cost.

---

## Teardown

Full reversal, in the exact reverse order of creation so nothing references a resource that's already gone:

```bash
cd multi-agent-fsi-blog

# 1. Delete the ArgoCD app-of-apps. Tofu Controller sees the Terraform CR
#    being deleted and runs `terraform destroy` inside the cluster, which
#    removes AgentCore Memory/Browser/CodeInterpreter and the IAM role.
kubectl delete application platform-root -n argocd
# Wait for children to fully drain (~2 min):
kubectl get application -n argocd -w

# 2. Destroy the bootstrap stack (ArgoCD + root Application).
cd terraform/bootstrap
terraform destroy -auto-approve -var "cluster_name=finops-agents"

# 3. Destroy the cluster + VPC + IAM.
cd ../cluster
terraform destroy -auto-approve -var "cluster_name=finops-agents"
```

If step 1 stalls (usually because a Crossplane MR can't reach AWS to `Delete`), clear finalizers one layer at a time:

```bash
# Let ArgoCD finish pruning first:
kubectl patch application financial-services -n argocd \
  -p '{"metadata":{"finalizers":null}}' --type=merge

# Then any stuck AgentCore MR (one-liner per type):
kubectl -n financial-services get memories,browsers,codeinterpreters -o name \
  | xargs -r -I{} kubectl patch {} -n financial-services \
      -p '{"metadata":{"finalizers":null}}' --type=merge

# Same treatment for per-agent IAM + Pod Identity MRs:
kubectl -n financial-services get roles.iam.aws.upbound.io,rolepolicies.iam.aws.upbound.io,podidentityassociations.eks.aws.upbound.io -o name \
  | xargs -r -I{} kubectl patch {} -n financial-services \
      -p '{"metadata":{"finalizers":null}}' --type=merge

# Finally, sweep any AWS resources whose CRs were force-deleted:
#   Bedrock AgentCore → delete fs_*_memory / fs_*_browser / fs_*_code_interpreter
#   IAM → delete fs-*-agent-role
#   EKS → delete financial-services/* Pod Identity associations
```

---

## Trade-offs worth naming in the blog post

- **LiteLLM hop** adds ~30–80 ms per inference. Worth it for unified spend tracking, retry, and fallback; but if a reader wants Bedrock-direct, `LITELLM_URL=""` in the agent env makes `_shared/model.py` fall back to the Bedrock provider.
- **Agent Gateway is not the Google A2A spec.** This walkthrough uses plain JSON over HTTP to `/agents/<name>`. For A2A-spec-compliant interop, wrap the agent's FastAPI `POST /` handler with the task/artifact envelope.
- **Browser reliability.** Yahoo Finance layout drifts. The market-data agent already falls back to MCP deterministic prices on scraping failures — fine for a demo, not for production.
- **JWKS is pinned in-chart.** Inline JWKS is simple and fast; rotation is `terraform apply`. For automatic rotation, swap `jwks.inline` for `jwks.remote` pointing at an in-cluster proxy with the EKS issuer cert installed.
- **Role sharing.** `finops-agents-crossplane-aws-provider` is currently reused by the Crossplane AWS providers, LiteLLM, and every agent Pod (via its per-agent IAM role). Fine for a demo; production deployments should split into per-workload roles scoped to exactly the AWS APIs each workload calls.

---

## Where to go next

- Put Keycloak in front of Agent Gateway for external-facing auth instead of Kubernetes SA tokens — the `jwtAuthentication.providers` list takes multiple entries, so you can accept both.
- Add a second specialist (e.g. `compliance-agent`) using the same template to show the platform scales.
- Replace the deterministic MCP tools with a real data provider (Bloomberg, Alpaca, etc.).
- Swap the demo LiteLLM masterkey for an External Secrets / AWS Secrets Manager lookup.
- Turn on Prometheus scraping for Agent Gateway + LiteLLM and add a Grafana dashboard for the FinOps story.
