# Measuring the Four DORA Metrics on EKS: A Hands-On Walkthrough

This guide stands up a full platform-engineering stack on Amazon EKS — Argo CD,
kro, Argo Workflows/Events, Gitea, Argo Rollouts, and Apache DevLake — and then
walks through **generating and verifying each of the four DORA metrics** on the
running cluster. Deployments record themselves automatically through Argo
Rollouts notifications, and Gitea issues/PRs flow into DevLake through Argo
Events, so once it's wired up you just *use* the platform and watch the metrics
move.

---

## 1. Deploy the cluster and platform

You just cloned the repo. Here's the shortest path from zero to a working stack.

**Prerequisites:** `eksctl`, `kubectl`, `helm`, the `kubectl-argo-rollouts`
plugin, `jq`, and AWS credentials that can create EKS clusters, VPCs, and IAM
roles.

```bash
# 1. Create the EKS cluster (EKS Auto Mode, ~15-20 min) and install the platform.
./scripts/00-create-cluster.sh
./scripts/10-install-argocd.sh                 # Argo CD + kro
./scripts/20-install-argo-workflows-events.sh  # Argo Workflows + Argo Events
./scripts/30-install-gitea.sh                  # self-hosted Git server
./scripts/40-install-argo-rollouts.sh
./scripts/50-install-devlake.sh                # DevLake + MySQL + Grafana
```

**Seed Gitea** with the demo repo (DevLake needs commits for Lead Time):

```bash
kubectl -n gitea port-forward svc/gitea-http 3000:3000 &
# In the UI (http://localhost:3000, gitea_admin / gitea_admin_pass) create a
# repo named "dora-demo" under gitea_admin, then push this repo's app/ folder:
git init dora-demo && cd dora-demo
cp -r ../app/* .
git add . && git commit -m "initial demo app"
git remote add origin http://gitea_admin:gitea_admin_pass@localhost:3000/gitea_admin/dora-demo.git
git branch -M main && git push -u origin main
cd ..
```

**Wire up DevLake** — create the project/webhook/blueprint, the Gitea webhooks,
and automatic deployment recording:

```bash
# Project + webhook connection + blueprint (also writes the shared credentials).
kubectl -n devlake port-forward svc/devlake-lake 8080:8080 &
./scripts/52-setup-devlake-project.sh

# Gitea issue + PR webhooks -> DevLake (reuses the credentials from script 52).
./scripts/55-configure-gitea-webhooks.sh

# Automatic deployment recording (use the connection id script 52 printed).
export DEVLAKE_WEBHOOK_URL="http://devlake-ui.devlake.svc.cluster.local:4000/api/rest/plugins/webhook/connections/1/deployments"
./scripts/60-configure-rollout-notifications.sh
```

**Deploy the demo app:**

```bash
kubectl apply -f app/namespace.yaml
kubectl apply -f app/services.yaml
kubectl apply -f app/rollout.yaml
```

You now have a cluster where every deploy and every Gitea issue/PR is captured
by DevLake. Throughout the sections below, refresh the metrics on demand with:

```bash
kubectl -n devlake port-forward svc/devlake-lake 8080:8080 &   # if not already
./scripts/70-calculate-metrics.sh
```

…and view them in Grafana (served by the config UI under /grafana):

```bash
kubectl -n devlake port-forward svc/devlake-ui 4000:4000 &
# http://localhost:4000/grafana/ -> the DORA dashboard
# Login: user 'admin'; password is generated — fetch it with:
#   kubectl -n devlake get secret devlake-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
```

> **How a deploy is recorded:** `ship.sh` sets the Rollout's image and stamps the
> commit SHA. When the rollout reaches **Healthy**, the Argo Rollouts controller
> auto-posts a `SUCCESS` deployment to DevLake; if you **abort**, it posts a
> `FAILURE`. No manual curl anywhere.

---

## 2. Deployment Frequency

**What it measures:** how often you successfully ship to production.

**Generate it** — ship a version and promote it through the canary to Healthy:

```bash
# Ship a new image tag (blue, green, red, orange, purple, yellow all work).
./scripts/ship.sh green

# Watch the canary: 20% -> pause 30s -> 50% -> manual pause -> 100%.
kubectl argo rollouts get rollout dora-demo -n dora-demo --watch

# At the 50% manual pause, promote it:
kubectl argo rollouts promote dora-demo -n dora-demo
```

When the rollout goes **Healthy**, a `SUCCESS` deployment is recorded. Repeat a
few times with different tags to build a trend:

`ship.sh` only starts the rollout (the canary takes ~30s+ to reach a pause), so
wait until it's actually `Paused` before promoting, then `promote --full` drives
it to `Healthy`. A bare `promote` fired immediately would skip the timed pause
and then stall at the indefinite manual gate.

```bash
for tag in blue green orange purple; do
  ./scripts/ship.sh "$tag"
  until [ "$(kubectl -n dora-demo get rollout dora-demo -o jsonpath='{.status.phase}')" = "Paused" ]; do
    sleep 3
  done
  kubectl argo rollouts promote dora-demo -n dora-demo --full
  kubectl argo rollouts status dora-demo -n dora-demo   # blocks until Healthy
done
```

**Verify it:**

```bash
./scripts/70-calculate-metrics.sh
```

Open the DORA dashboard in Grafana — **Deployment Frequency** now shows one
count per promoted rollout over time.

---

## 3. Lead Time for Changes

**What it measures:** how long a change takes to go from a merged PR to
production. This metric is **PR-based** — it needs a merged pull request.

**How the link works:** merging a PR fires the Gitea webhook, which posts a
pull-request record to DevLake carrying `createdDate`, `mergedDate`, and the
PR's **merge commit SHA**. The deployment record carries the commit SHA it
shipped. DevLake matches the deployment SHA to the PR's `merge_commit_sha` and
computes lead time = *deploy finished − PR opened*. So you must **deploy the
PR's merge commit**, not the branch tip — otherwise the deploy never links to
the PR. (No gitextractor/refdiff needed; it's all webhook-fed.)

**Generate it** — branch → commit → open PR → merge → ship the merge commit
(Gitea must be reachable at `http://localhost:3000`):

```bash
cd dora-demo
git checkout -b lead-time-demo
echo "// change $(date -u +%FT%TZ)" >> services.yaml
git commit -am "adjust demo service"
git push -u origin lead-time-demo
cd ..

# Open a PR and merge it (fires the webhook that records the PR).
GT="http://gitea_admin:gitea_admin_pass@localhost:3000/api/v1/repos/gitea_admin/dora-demo"
PR=$(curl -sS -X POST "$GT/pulls" -H 'Content-Type: application/json' \
  -d '{"head":"lead-time-demo","base":"main","title":"Adjust demo service"}' | jq -r '.number')
curl -sS -X POST "$GT/pulls/$PR/merge" -H 'Content-Type: application/json' -d '{"Do":"merge"}'

# Ship the PR's merge commit so the deployment links to the merged PR.
MERGE_SHA=$(curl -sS "$GT/pulls/$PR" | jq -r '.merge_commit_sha')
./scripts/ship.sh green "$MERGE_SHA"
until [ "$(kubectl -n dora-demo get rollout dora-demo -o jsonpath='{.status.phase}')" = "Paused" ]; do sleep 3; done
kubectl argo rollouts promote dora-demo -n dora-demo --full
```

**Verify it:**

```bash
./scripts/70-calculate-metrics.sh
```

In Grafana, **Lead Time for Changes** reports the median PR-merge→deploy
duration. If it's empty, the usual cause is a **SHA mismatch** — the deploy was
shipped with the branch-tip SHA instead of the PR's `merge_commit_sha`, so it
never links to the PR.

---

## 4. Change Failure Rate

**What it measures:** the share of deployments that led to a failure in
production. **DevLake decides "failed" by incidents, not by the rollout
outcome** — it links an incident to a deployment **by timestamp** (an incident
created after a deployment, before the next one, marks that deployment as a
failure). An *incident* is a Gitea **issue** (`type=INCIDENT`). So
`CFR = deployments followed by an incident ÷ total`, and aborting a rollout
alone does **not** move CFR — **opening an issue after the deploy does.**

**Generate it** — ship a version, then file the incident it caused:

```bash
# 1. Ship a "bad" version (promote or abort — either records a deployment).
./scripts/ship.sh red
until [ "$(kubectl -n dora-demo get rollout dora-demo -o jsonpath='{.status.phase}')" = "Paused" ]; do sleep 3; done
kubectl argo rollouts promote dora-demo -n dora-demo --full

# 2. Open a Gitea issue AFTER the deploy — its timestamp links it to that
#    deployment, marking it a change failure. (Gitea must be reachable.)
GT="http://gitea_admin:gitea_admin_pass@localhost:3000/api/v1/repos/gitea_admin/dora-demo"
ISSUE=$(curl -sS -X POST "$GT/issues" -H 'Content-Type: application/json' \
  -d '{"title":"Checkout returns 500 after deploy","body":"Elevated 5xx in production"}' | jq -r '.number')
echo "opened incident issue #$ISSUE"   # section 5 closes this
```

**Verify it:**

```bash
./scripts/70-calculate-metrics.sh
```

**Change Failure Rate** in Grafana = deployments followed by an incident ÷
total deployments. If it stays flat, the incident didn't link: no
`INCIDENT`-typed issue reached DevLake (check `dora-incident-workflow` ran), or
the issue's timestamp is before the deployment it should mark.

---

## 5. Time to Restore Service

**What it measures:** how long it takes to recover from an incident. Like CFR,
this is **incident-driven**: DevLake measures the span from the incident's
`createdDate` to its `resolutionDate` — i.e. from opening the Gitea issue to
**closing** it. So the metric is really about resolving the incident from
Section 4.

**Generate it** — restore service, then close the incident:

```bash
# 1. Ship the known-good version (the real recovery; records a healthy deploy).
./scripts/ship.sh green
until [ "$(kubectl -n dora-demo get rollout dora-demo -o jsonpath='{.status.phase}')" = "Paused" ]; do sleep 3; done
kubectl argo rollouts promote dora-demo -n dora-demo --full

# 2. Close the incident issue from Section 4 — this is what DevLake measures.
curl -sS -X PATCH "$GT/issues/$ISSUE" -H 'Content-Type: application/json' -d '{"state":"closed"}'
```

**Verify it:**

```bash
./scripts/70-calculate-metrics.sh
```

In Grafana, **Time to Restore Service** shows the median incident open→resolved
duration. If empty, the issue was never closed (no `resolutionDate`) or the
close event didn't reach DevLake.

---

### Quick reference

| Metric | Generate | Records as |
|---|---|---|
| Deployment Frequency | `ship.sh <tag>` → `promote` | `SUCCESS` |
| Lead Time for Changes | commit + push, then `ship.sh <tag> <sha>` → `promote` | `SUCCESS` + commit SHA |
| Change Failure Rate | `ship.sh <tag>` → `abort` | `FAILURE` (+ optional incident issue) |
| Time to Restore Service | after a failure, `ship.sh <good>` → `promote` | `SUCCESS` following a `FAILURE` |

After any of these, run `./scripts/70-calculate-metrics.sh` and refresh the DORA
dashboard in Grafana.
