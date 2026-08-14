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
export DEVLAKE_WEBHOOK_URL="http://devlake-config-ui.devlake.svc.cluster.local:4000/api/rest/plugins/webhook/connections/1/deployments"
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

…and view them in Grafana:

```bash
kubectl -n devlake port-forward svc/devlake-grafana 3001:3000 &
# http://localhost:3001  (admin / admin) -> the DORA dashboard
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

```bash
for tag in blue green orange purple; do
  ./scripts/ship.sh "$tag"
  kubectl argo rollouts promote dora-demo -n dora-demo
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

**What it measures:** the time from a commit landing in `main` to that change
being deployed to production.

The key is that the deployment record must carry the **commit SHA** — `ship.sh`
stamps it onto the Rollout, and DevLake joins it against the commit it collected
from Gitea.

**Generate it** — make a real commit, then ship *that* commit:

```bash
cd dora-demo
echo "// tweak $(date -u +%FT%TZ)" >> services.yaml
git commit -am "adjust demo service"
git push origin main
SHA="$(git rev-parse HEAD)"
cd ..

# Ship, passing the commit SHA so DevLake can compute commit -> deploy time.
./scripts/ship.sh green "$SHA"
kubectl argo rollouts promote dora-demo -n dora-demo
```

> `ship.sh green` on its own will auto-detect `HEAD` of a local `./dora-demo`
> clone, so if you're working inside that clone you can skip the explicit SHA.

**Verify it:**

```bash
./scripts/70-calculate-metrics.sh
```

In Grafana, **Lead Time for Changes** reports the median commit→deploy duration.
Make sure DevLake has collected the Gitea commits (the blueprint run above does
this) — a deploy whose SHA has no matching commit won't contribute.

---

## 4. Change Failure Rate

**What it measures:** the share of deployments that fail (require a rollback,
fix, or otherwise degrade service).

**Generate it** — ship a version and **abort** at the canary gate, simulating a
bad deploy caught in production:

```bash
# Ship a "bad" version.
./scripts/ship.sh red
kubectl argo rollouts get rollout dora-demo -n dora-demo --watch

# Decide it's broken and abort — this rolls back to the stable version.
kubectl argo rollouts abort dora-demo -n dora-demo
```

The rollout goes **Degraded/aborted** and a `FAILURE` deployment is recorded.

Optionally, log the customer-facing incident too — open an issue in the
`dora-demo` repo (**Issues → New Issue** in the Gitea UI). The Gitea webhook
routes it through Argo Events to DevLake as an `INCIDENT`, which enriches the
failure signal.

**Verify it:**

```bash
./scripts/70-calculate-metrics.sh
```

**Change Failure Rate** in Grafana = `FAILURE` deployments ÷ total deployments.
Mix in the successful deploys from Section 2 and you'll see a realistic rate
rather than 0% or 100%.

> **Ordering tip:** if you file incidents *after* deployments were already
> collected, re-run `70-calculate-metrics.sh` so incidents map to the right
> deployments by timestamp — otherwise CFR may not render.

---

## 5. Time to Restore Service

**What it measures:** how long it takes to recover after a failed deploy /
incident.

This builds directly on Section 4: you have a `FAILURE` on the record, now
**restore service** by shipping a known-good version and promoting it.

**Generate it:**

```bash
# Ship the known-good version again and promote it through to Healthy.
./scripts/ship.sh green
kubectl argo rollouts promote dora-demo -n dora-demo
kubectl argo rollouts status dora-demo -n dora-demo   # waits for Healthy
```

The recovery records a `SUCCESS`. **Time to Restore Service** is the gap between
that `SUCCESS` and the preceding `FAILURE` in `PRODUCTION`.

If you opened an incident issue in Section 4, **close it** in Gitea now — the
webhook posts the resolution, and DevLake uses the issue's open→close span as an
additional restore-time signal.

**Verify it:**

```bash
./scripts/70-calculate-metrics.sh
```

In Grafana, **Time to Restore Service** shows the median failure→recovery
duration. Run the fail-then-restore cycle a couple of times to build a trend.

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
