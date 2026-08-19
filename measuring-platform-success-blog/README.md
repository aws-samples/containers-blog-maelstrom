# Measuring DORA Metrics with Apache DevLake on EKS

A hands-on, end-to-end showcase that stands up a full platform-engineering
stack on Amazon EKS and uses it to **measure the four DORA metrics** against a
real application that deploys via **Argo Rollouts**.

> **Looking for the blog post?** [`blog.md`](./blog.md) is the reader-facing
> narrative version of this walkthrough (the draft that ships to the AWS
> Containers Blog). This README is the terser engineer-facing how-to.

By the end you will have:

- An **EKS cluster** created with `eksctl`, with **Argo CD** and **kro**
  installed (self-hosted) on top.
- **Argo Workflows** and **Argo Events** installed.
- **Gitea** as a self-hosted Git server (the source of commit/PR data).
- **Apache DevLake** with **Grafana** and **MySQL** enabled (the DORA engine).
- **Argo Rollouts** driving a demo app whose promotions, aborts, and rollbacks
  populate all four DORA metrics — recorded in DevLake **automatically** via
  Argo Rollouts notifications (no manual `curl`; you just ship a change).

> The four DORA metrics: **Deployment Frequency**, **Lead Time for Changes**,
> **Change Failure Rate**, and **Time to Restore Service** (a.k.a. MTTR / Failed
> Deployment Recovery Time).

---

## Table of contents

1. [Architecture](#1-architecture)
2. [Prerequisites](#2-prerequisites)
3. [Repository layout](#3-repository-layout)
4. [Quick start (TL;DR)](#4-quick-start-tldr)
5. [Step-by-step install](#5-step-by-step-install)
6. [Seed Gitea with the demo repo](#6-seed-gitea-with-the-demo-repo)
7. [Set up the DevLake project + webhooks](#7-set-up-the-devlake-project--webhooks)
8. [Deploy the demo app (Argo Rollout)](#8-deploy-the-demo-app-argo-rollout)
9. [Automatic deployment recording](#9-automatic-deployment-recording)
10. [The DORA walkthrough — drive every metric](#10-the-dora-walkthrough--drive-every-metric)
11. [Read the metrics in Grafana](#11-read-the-metrics-in-grafana)
12. [Teardown](#12-teardown)
13. [Troubleshooting](#13-troubleshooting)

---

## 1. Architecture

```
                          ┌──────────────────────────────────────────────┐
                          │                  EKS cluster                   │
                          │                                                │
   git push / PR   ┌──────┴──────┐    collect        ┌───────────────┐     │
   ───────────────▶│    Gitea    │◀──────────────────│    DevLake     │     │
                   │ (git server)│                    │  lake + MySQL  │     │
                   └──────┬──────┘                    │  + config-ui   │     │
                          │                           └───────┬────────┘     │
                          │ ArgoCD sync (GitOps)              │ render        │
                          ▼                                   ▼               │
                   ┌─────────────┐  auto notification  ┌───────────────┐     │
                   │Argo Rollouts│──── webhook ───────▶│    Grafana     │     │
                   │  demo app   │ (Healthy=SUCCESS,    │  DORA dashboard│     │
                   │             │  Degraded=FAILURE)   │                │     │
                   └─────────────┘         │           └───────────────┘     │
                          │                └──▶ DevLake webhook (deployments) │
                          ▲                                                   │
        Argo CD ── kro ── Argo Workflows ── Argo Events (platform capabilities)│
                          └──────────────────────────────────────────────────┘
```

**How the data flows into each DORA metric:**

| DORA metric               | Data source                                             | How it's produced here                                                          |
|---------------------------|---------------------------------------------------------|---------------------------------------------------------------------------------|
| Deployment Frequency      | DevLake deployments (auto webhook)                      | Rollout reaching **Healthy** auto-posts a `SUCCESS` deployment.                 |
| Lead Time for Changes     | Gitea commits + deployment `commitSha`                  | Time from commit → the deployment that shipped it (SHA stamped by `ship.sh`).   |
| Change Failure Rate       | DevLake deployments (auto webhook)                      | Rollout **Degraded/aborted** auto-posts a `FAILURE` deployment.                 |
| Time to Restore Service   | DevLake deployments (auto webhook)                      | Time from a `FAILURE` to the next `SUCCESS` in the same env.                    |

---

## 2. Prerequisites

Install these locally first:

| Tool                     | Why                          | Install                                                                 |
|--------------------------|------------------------------|-------------------------------------------------------------------------|
| AWS CLI (v2)             | Auth to AWS                  | https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html |
| `eksctl`                 | Create the EKS cluster       | https://eksctl.io/installation/                                         |
| `kubectl`                | Talk to the cluster          | https://kubernetes.io/docs/tasks/tools/                                 |
| `helm` (v3)              | Install Gitea + DevLake      | https://helm.sh/docs/intro/install/                                     |
| `kubectl-argo-rollouts`  | Promote/abort the rollout    | `brew install argoproj/tap/kubectl-argo-rollouts`                       |
| `git`, `curl`, `jq`      | Seed repo + post webhooks    | your package manager                                                     |

You also need **AWS credentials** with permission to create EKS clusters, VPCs,
and IAM roles. Confirm with:

```bash
aws sts get-caller-identity
```

> **Cost note:** this creates an EKS control plane plus EKS Auto Mode compute
> (EC2 instances Auto Mode launches on demand) and EBS volumes. Remember to run
> the [teardown](#12-teardown) when done.

---

## 3. Repository layout

```
.
├── README.md                      # you are here
├── cluster/
│   └── cluster.yaml               # eksctl ClusterConfig (EKS Auto Mode)
├── scripts/
│   ├── install-platform.sh        # ONE-SHOT wrapper: runs 00-50 in order with timing
│   ├── 00-create-cluster.sh       # eksctl create cluster
│   ├── 10-install-argocd.sh       # Argo CD + kro
│   ├── 20-install-argo-workflows-events.sh
│   ├── 30-install-gitea.sh
│   ├── 40-install-argo-rollouts.sh
│   ├── 50-install-devlake.sh      # DevLake + MySQL + Grafana
│   ├── 52-setup-devlake-project.sh  # project + webhook connection + blueprint
│   ├── 55-configure-gitea-webhooks.sh  # Gitea issue/PR webhooks -> DevLake
│   ├── 60-configure-rollout-notifications.sh  # auto-record deploys to DevLake
│   ├── 70-calculate-metrics.sh    # trigger the blueprint -> compute DORA metrics
│   ├── port-forward.sh            # start/stop all browser-facing tunnels at once
│   ├── lib/pf.sh                  # sourced helper: scripts auto-manage their own tunnel
│   ├── ship.sh                    # THE deploy command (stamps sha + sets image)
│   └── record-deployment.sh       # manual fallback: post a deploy event by hand
├── platform/
│   ├── argocd/dora-demo-app.yaml  # optional GitOps Application for the demo
│   ├── argo-rollouts/notifications-configmap.yaml # triggers + webhook payloads
│   ├── argo-rollouts/notifications-secret.yaml    # DevLake webhook URL
│   ├── webhooks/gitea-eventsource.yaml   # Argo Events endpoint Gitea posts to
│   ├── webhooks/gitea-sensor.yaml        # routes issues/PRs by X-Gitea-Event
│   ├── webhooks/gitea-sensor-rbac.yaml   # lets the Sensor submit Workflows
│   ├── webhooks/dora-workflowtemplates.yaml # Gitea->DevLake jq transforms
│   ├── webhooks/devlake-webhook-config.yaml # reference/fallback for the creds
                                              # (script 52 creates the real ones)
│   ├── kro/dora-demo-rgd.yaml     # optional kro ResourceGraphDefinition
│   ├── kro/dora-demo-instance.yaml
│   ├── gitea/values.yaml          # Gitea Helm values
│   └── devlake/values.yaml        # DevLake Helm values (mysql + grafana on)
├── app/
│   ├── namespace.yaml
│   ├── services.yaml              # stable + canary Services
│   ├── rollout.yaml               # the Argo Rollout (canary + notif subscriptions)
│   └── README-app.md              # notes on the demo app
├── docs/
│   └── dora-metrics.md            # deeper explanation of each metric
├── images/                        # screenshot targets referenced by blog.md
│   └── README.md
└── blog.md                        # reader-facing narrative blog draft (publishable)
```

---

## 4. Quick start (TL;DR)

```bash
# 0. Grab the code (this blog folder lives inside the containers-blog-maelstrom repo).
git clone https://github.com/aws-samples/containers-blog-maelstrom.git
cd containers-blog-maelstrom/measuring-platform-success-blog

# 1. Stand up everything (single wrapper — runs 00→50 with per-stage banners & timing).
./scripts/install-platform.sh

# 2. Deploy the demo app
kubectl apply -f app/namespace.yaml
kubectl apply -f app/services.yaml
kubectl apply -f app/rollout.yaml

# 3. (Optional) open the browser UIs (Gitea, DevLake config-ui, Grafana):
./scripts/port-forward.sh          # stop later with: ./scripts/port-forward.sh stop

#    Seed Gitea with the demo repo (section 6), then set up DevLake.
#    Scripts 52/55/70 auto-open a temporary tunnel if one isn't already up,
#    so no manual `kubectl port-forward` is required.
#    Project + webhook connection + blueprint (creates the shared creds):
./scripts/52-setup-devlake-project.sh

#    Gitea issue/PR webhooks -> DevLake (uses the creds from 52):
./scripts/55-configure-gitea-webhooks.sh

#    Automatic deployment recording (connection id printed by script 52):
export DEVLAKE_WEBHOOK_URL="http://devlake-ui.devlake.svc.cluster.local:4000/api/rest/plugins/webhook/connections/1/deployments"
./scripts/60-configure-rollout-notifications.sh

# 4. Ship changes — deployments record themselves:
./scripts/ship.sh green      # ...then promote or abort; DevLake logs it automatically

# 5. Compute the DORA metrics so Grafana shows them:
./scripts/70-calculate-metrics.sh
```

Then jump to the [DORA walkthrough](#10-the-dora-walkthrough--drive-every-metric).

---

## 5. Step-by-step install

**TL;DR:** `./scripts/install-platform.sh` runs 5.1 → 5.6 in order with a
per-stage banner and timing. Read on if you'd rather drive each step yourself.

Run the scripts in order. Each one prints the port-forward command and
credentials for the component it installs.

### 5.1 Create the cluster

```bash
./scripts/00-create-cluster.sh
```

Provisions the cluster from `cluster/cluster.yaml` with EKS Auto Mode: AWS
manages compute (the `general-purpose` + `system` node pools), block storage,
and networking, and the EKS Pod Identity Agent is preinstalled for granting
workloads scoped IAM. The script also creates a gp3 default StorageClass (Auto
Mode ships none) so MySQL/Grafana PVCs can bind. Takes ~15–20 minutes.

### 5.2 Install Argo CD + kro

```bash
./scripts/10-install-argocd.sh
```

Installs Argo CD into the `argocd` namespace and the kro controller into `kro`.
At the end it prints the auto-generated Argo CD `admin` password.

**Log in to Argo CD:**

```bash
# Grab the initial admin password (also printed by the script):
kubectl -n argocd get secret argocd-initial-admin-secret \
  -o jsonpath="{.data.password}" | base64 -d && echo

# Port-forward the server, then open https://localhost:8080
kubectl -n argocd port-forward svc/argocd-server 8080:443
# Username: admin   Password: (the value above)
```

> Rotate or delete `argocd-initial-admin-secret` after first login for anything
> beyond a throwaway demo.

### 5.3 Install Argo Workflows + Argo Events

```bash
./scripts/20-install-argo-workflows-events.sh
```

### 5.4 Install Gitea

```bash
./scripts/30-install-gitea.sh
```

Default creds: `gitea_admin` / `gitea_admin_pass` (set in
`platform/gitea/values.yaml` — change them for anything real).

### 5.5 Install Argo Rollouts

```bash
./scripts/40-install-argo-rollouts.sh
```

### 5.6 Install DevLake (MySQL + Grafana)

```bash
./scripts/50-install-devlake.sh
```

Exposes:
- **config-ui** on `:4000` — where you set up connections/blueprints. It also
  proxies **Grafana** under `/grafana`, so the DORA dashboards are at
  `http://localhost:4000/grafana/`. Don't port-forward Grafana directly — it's
  pinned to serve at `/grafana` and redirects to `localhost:3000`, colliding
  with Gitea. Log in as `admin`; the password is generated — fetch it with
  `kubectl -n devlake get secret devlake-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo`.

### 5.7 Set up the DevLake project + webhooks + deployment recording

These depend on data flowing into a DevLake project, so they come after you've
seeded Gitea (section 6). In order:

1. **Project + webhook connection + blueprint** — section 7.1 / `52-setup-devlake-project.sh`
2. **Gitea issue + PR webhooks** — section 7.2 / `55-configure-gitea-webhooks.sh`
3. **Automatic deployment recording** — section 7.3 / `60-configure-rollout-notifications.sh`

Then compute the metrics with `70-calculate-metrics.sh` (section 11).

---

## 6. Seed Gitea with the demo repo

DevLake needs commits to compute Lead Time. Create a repo in Gitea and push the
`app/` manifests to it.

```bash
# Port-forward Gitea in one terminal:
kubectl -n gitea port-forward svc/gitea-http 3000:3000

# In the Gitea UI (http://localhost:3000, gitea_admin / gitea_admin_pass):
#   - Create a new repository named "dora-demo" under gitea_admin.

# Then push this blog folder's app/ manifests to it (using a scratch clone so
# you don't pollute the maelstrom repo working tree):
mkdir -p /tmp/dora-demo && cp -r app/* /tmp/dora-demo/
cd /tmp/dora-demo
git init -b main
git add . && git commit -m "initial demo app"
git remote add origin http://gitea_admin:gitea_admin_pass@localhost:3000/gitea_admin/dora-demo.git
git push -u origin main
cd -   # back to measuring-platform-success-blog
```

Grab a **personal access token** from Gitea (Settings → Applications → Generate
Token) — DevLake uses it to read the repo.

---

## 7. Set up the DevLake project + webhooks

DevLake computes DORA metrics **per project**, and only when that project's
**blueprint** runs. So the flow is: create a project (with a webhook connection
attached to its blueprint) → feed it data (deployments + Gitea issues/PRs) →
trigger the blueprint to compute metrics (section 11).

> **API base URL note:** the DevLake **lake** backend serves its API at the root
> of port **8080** (`/projects`, `/blueprints/:id`, …). The `/api/rest/...`
> prefix only exists on the **config-ui** proxy (port **4000**). Scripts 52 and
> 70 talk to the lake backend, so they use bare paths; the webhook POST URLs
> below go through config-ui, so they keep the `/api/rest` prefix.

**7.1 Create the project, webhook connection, and blueprint** (automated).

```bash
# The script talks to the lake backend API. It auto-opens a temporary
# port-forward if one isn't already up (or reuses ./scripts/port-forward.sh):
./scripts/52-setup-devlake-project.sh
```

This creates a `dora-demo` project with the `dora` + `issue_trace` metrics, an
Incoming Webhook connection, and attaches that connection to the project's
blueprint. It then writes the connection's **api key** and **id** (plus the
**blueprint id**) into `devlake-webhook-secret` / `devlake-webhook-id` in the
`argo` namespace — the credentials the Gitea webhook Workflows consume. The
connection id it prints is the `<ID>` used in the deployment webhook URL below.

**7.2 Wire Gitea issue + PR webhooks** (via Argo Events → Argo Workflows).
The Git-activity metrics (incidents from issues, code-review metrics from pull
requests) come from Gitea webhooks. Gitea POSTs each event to an Argo Events
endpoint; a Sensor routes it by the `X-Gitea-Event` header to an Argo
`WorkflowTemplate` that transforms the Gitea payload into a DevLake webhook
record. This reuses the credentials script 52 created, so run 52 first.

```bash
# Gitea must be reachable to register the webhook via its API. Like script 52,
# this auto-opens a temporary port-forward if one isn't already up:
./scripts/55-configure-gitea-webhooks.sh
```

The script applies the EventSource, Sensor, RBAC, and WorkflowTemplates, then
registers a `gitea`-type webhook (events: Issues, Pull Request) on the
`dora-demo` repo. Watch it work:

```bash
kubectl -n argo get workflows -l app.kubernetes.io/component=dora-webhooks -w
kubectl -n argo-events logs -l sensor-name=gitea-dora -f
```

> **Payload shape:** Gitea sends a GitHub-style payload (top-level `issue` /
> `pull_request` objects, RFC3339 timestamps, a boolean `merged`) — the jq
> transforms in `platform/webhooks/dora-workflowtemplates.yaml` target that
> shape, not GitLab's `object_attributes`.

**7.3 Turn on automatic deployment recording.** Point the Argo Rollouts
controller at the same webhook connection (use the `<ID>` script 52 printed).
The poster is the **controller running inside the cluster**, so use the
in-cluster config-ui DNS name, not `localhost`:

```bash
export DEVLAKE_WEBHOOK_URL="http://devlake-ui.devlake.svc.cluster.local:4000/api/rest/plugins/webhook/connections/1/deployments"
./scripts/60-configure-rollout-notifications.sh
```

This installs the notification ConfigMap + Secret so the controller posts a
deployment record to DevLake on its own. See [section 9](#9-automatic-deployment-recording)
for how it works.

> See `docs/dora-metrics.md` for the exact payload; the notification templates
> in `platform/argo-rollouts/notifications-configmap.yaml` build it for you.
> (`scripts/record-deployment.sh` remains as a manual fallback if you ever want
> to post one by hand.)

---

## 8. Deploy the demo app (Argo Rollout)

```bash
kubectl apply -f app/namespace.yaml
kubectl apply -f app/services.yaml
kubectl apply -f app/rollout.yaml
```

Watch it:

```bash
kubectl argo rollouts get rollout dora-demo -n dora-demo --watch
```

The app uses a **canary** strategy (20% → 50% → 100%) with a **manual pause**
at 50% — that pause is your promote/abort decision point. The Rollout is also
annotated to **subscribe to the DevLake notification triggers**, so once
section 5.7 is done, deployments record themselves.

> **Optional — GitOps & kro:** instead of `kubectl apply` you can let Argo CD
> manage the app (`platform/argocd/dora-demo-app.yaml`, after editing
> `repoURL`), or package it as a single `DoraDemoApp` resource with kro
> (`platform/kro/dora-demo-rgd.yaml` + `dora-demo-instance.yaml`).

---

## 9. Automatic deployment recording

You do **not** post deployments by hand. The Argo Rollouts controller ships
with a built-in notifications engine, and we've configured it to call DevLake's
Incoming Webhook whenever the Rollout changes state:

| Rollout state                     | Notification fired    | DevLake record | DORA impact                          |
|-----------------------------------|-----------------------|----------------|--------------------------------------|
| becomes `Healthy` (promoted)      | `on-deploy-success`   | `SUCCESS`      | Deployment Frequency, Lead Time      |
| `Degraded` / `abort == true`      | `on-deploy-failure`   | `FAILURE`      | Change Failure Rate                  |
| `FAILURE` → next `SUCCESS`        | (both, in sequence)   | —              | Time to Restore Service              |

The wiring lives in:

- `platform/argo-rollouts/notifications-configmap.yaml` — the triggers
  (`when` conditions, `oncePer` the pod-hash so each version fires once) and the
  DevLake JSON payload templates.
- `platform/argo-rollouts/notifications-secret.yaml` — the DevLake webhook URL.
- `app/rollout.yaml` — the `notifications.argoproj.io/subscribe.*` annotations
  and a `dora.dev/commit-sha` annotation that `ship.sh` stamps so DevLake can
  compute Lead Time.

Confirm notifications are firing:

```bash
kubectl -n argo-rollouts logs deploy/argo-rollouts -f | grep -i notif
```

---

## 10. The DORA walkthrough — drive every metric

Keep two terminals open:

- **T1:** `kubectl argo rollouts get rollout dora-demo -n dora-demo --watch`
- **T2:** your working shell

You **never call the webhook directly** — you ship a change and either promote
or abort. The controller records the deployment for you.

### 10.1 A healthy deploy → Deployment Frequency + Lead Time

```bash
# 1. Commit a change in the Gitea repo (this timestamps "when work was ready"),
#    e.g. edit a file in ./dora-demo, commit, and push to Gitea.

# 2. Ship it. ship.sh stamps the current commit sha onto the rollout and sets
#    the new image, starting the canary:
./scripts/ship.sh green

# 3. The rollout pauses at 50%. Inspect in T1, then promote:
kubectl argo rollouts promote dora-demo -n dora-demo
```

➡️ When the rollout reaches **Healthy**, the controller auto-posts a `SUCCESS`
deployment. **Deployment Frequency** ticks up, and because the record carries
the stamped `commitSha`, DevLake computes **Lead Time for Changes**.

Repeat a few times to build up a trend.

### 10.2 A bad deploy you abort → Change Failure Rate

```bash
# 1. Ship a "bad" version (any tag — pretend it's broken):
./scripts/ship.sh red

# 2. At the pause, decide it's bad and ABORT (rolls back to stable):
kubectl argo rollouts abort dora-demo -n dora-demo
```

➡️ The rollout goes **Degraded/aborted**, the controller auto-posts a `FAILURE`
deployment, and **Change Failure Rate** rises.

### 10.3 Restore service → Time to Restore Service

```bash
# Ship the known-good version again and promote it:
./scripts/ship.sh green
kubectl argo rollouts promote dora-demo -n dora-demo
```

➡️ The recovery auto-posts a `SUCCESS`. **Time to Restore Service** = this
`SUCCESS` timestamp − the preceding `FAILURE` timestamp in `PRODUCTION`.

### 10.4 Cheat sheet

| Action                         | Command                                                | Recorded automatically as → metric              |
|--------------------------------|--------------------------------------------------------|--------------------------------------------------|
| Ship a new version             | `./scripts/ship.sh <tag>`                              | (starts a rollout; stamps commit sha)            |
| Promote a good rollout         | `kubectl argo rollouts promote dora-demo -n dora-demo` | `SUCCESS` → Deployment Frequency, Lead Time      |
| Abort a bad rollout            | `kubectl argo rollouts abort dora-demo -n dora-demo`   | `FAILURE` → Change Failure Rate                  |
| Promote after a failure        | `kubectl argo rollouts promote dora-demo -n dora-demo` | `SUCCESS` → Time to Restore Service              |

---

## 11. Read the metrics in Grafana

If you didn't open the browser tunnels earlier, do it now:

```bash
./scripts/port-forward.sh          # then open http://localhost:4000/grafana/
```

Grafana is served by the config UI under `/grafana`, so it rides the same
`:4000` tunnel — open **http://localhost:4000/grafana/**. Log in as `admin`
with the generated password:

```bash
kubectl -n devlake get secret devlake-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

Open the **DORA** dashboard (provisioned by the DevLake chart). DevLake only
computes DORA metrics when the project's blueprint runs, so after generating
data (deploys, issues, PRs), trigger a computation. Script 70 auto-opens a
temporary tunnel to the lake backend if `./scripts/port-forward.sh` isn't
already handling it:

```bash
./scripts/70-calculate-metrics.sh
```

This triggers the blueprint (stored by script 52) and waits for the pipeline to
finish. Then the dashboard shows:

- **Deployment Frequency** — count/day from the auto `SUCCESS` records.
- **Lead Time for Changes** — median commit→deploy time.
- **Change Failure Rate** — `FAILURE` deployments ÷ total deployments.
- **Time to Restore Service** — median failure→recovery time.

> Re-run `70-calculate-metrics.sh` whenever you want to refresh the metrics
> (or wait for the blueprint's weekly cron). The blueprint also runs on its
> schedule, but the script gives you an on-demand recompute.
>
> **Change Failure Rate gotcha:** if you post incidents (issue webhooks) *after*
> deployments were already collected, re-run the calculation so incidents map to
> the right deployments by timestamp — otherwise CFR may not render.

---

## 12. Teardown

```bash
# App + platform (optional; deleting the cluster removes all of it anyway)
kubectl delete -f app/ --ignore-not-found

# The big one — deletes the EKS cluster (incl. Auto Mode compute) and VPC:
eksctl delete cluster -f cluster/cluster.yaml --wait
```

> Double-check in the AWS console that the CloudFormation stacks, EBS volumes,
> and any leftover load balancers are gone to avoid surprise charges.

---

## 13. Troubleshooting

| Symptom                                             | Fix                                                                                          |
|-----------------------------------------------------|----------------------------------------------------------------------------------------------|
| MySQL/Grafana pod stuck `Pending`                   | No default StorageClass. `00-create-cluster.sh` creates a gp3 default — re-run that step.     |
| DevLake pods `CrashLoopBackOff` on first boot       | MySQL wasn't ready yet; DevLake retries. Give it a few minutes, then check `kubectl -n devlake logs deploy/devlake-lake`. |
| No deployments recorded after promote/abort         | Notifications not firing. Check `kubectl -n argo-rollouts logs deploy/argo-rollouts \| grep -i notif`, and confirm the Rollout has the `notifications.argoproj.io/subscribe.*` annotations. |
| Notification error: connection refused / 404        | The Secret `devlake-webhook-url` must be the **in-cluster** URL (`devlake-lake.devlake.svc…`), not `localhost`, and the connection **id** must match the config UI. Re-run `60-configure-rollout-notifications.sh` with the right `DEVLAKE_WEBHOOK_URL`. |
| Only one deploy recorded per version                | Expected — `oncePer: currentPodHash` dedupes per version. Ship a *different* image tag to fire again. |
| Rollout never leaves the pause                      | It's a *manual* pause by design — run `kubectl argo rollouts promote dora-demo -n dora-demo`.  |
| No Lead Time showing                                | The deploy's `dora.dev/commit-sha` was `initial`/`unknown` (ship via `ship.sh`), or DevLake hasn't collected Gitea commits. Re-run the Blueprint. |
| Grafana shows nothing                               | DevLake collection hasn't run since your last deploy. Trigger the Blueprint manually.          |

---

## Further reading

- `docs/dora-metrics.md` — what each metric means and how DevLake computes it.
- [Apache DevLake docs](https://devlake.apache.org/docs/DORA)
- [Argo Rollouts docs](https://argo-rollouts.readthedocs.io/)
- [DORA / DevOps research](https://dora.dev/)
