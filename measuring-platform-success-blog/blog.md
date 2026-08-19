<!--
Publication draft of the "Measuring Platform Success" blog. This file is the
narrative version reviewers comment on and that ultimately becomes the AWS
Containers Blog post. The sibling README.md is the how-to for engineers running
the code locally — keep the two consistent, but this file is the reader-facing
one.
-->

# Beyond Uptime: Measuring the Developer Experience Impact of an EKS Internal Developer Platform

Platform engineering has become a cornerstone of modern software delivery, yet
a critical question often goes unanswered: how do you know if your platform is
actually working? For many teams, the honest answer is that they don't.
According to the *State of Platform Engineering Report Volume 4*, 29.6% of
platform teams don't measure success at all, and another 24.2% can't tell
whether their metrics have improved. That means more than half of all platform
teams are either flying blind or collecting data without turning it into
insight.

This is more than a reporting inconvenience. It creates an accountability gap
that puts platform funding at risk and undermines your ability to prove the
platform is worth the investment. When you can't measure your platform, you
can't pinpoint bottlenecks, make evidence-based decisions about where to invest
next, or show leadership a return. The cost of that blind spot is real: 71% of
leading platform adopters have accelerated their time to market (Platform
Engineering Research Report), but a team that isn't measuring has no way to
claim that value, or even to know whether they've captured it.

So how do you measure the success of your platform? The industry has converged
on an answer: DevOps Research and Assessment (DORA) metrics. At 40.8% adoption,
DORA metrics are the most widely used measurement framework among platform
teams, followed by time to market (31.0%) and SPACE (Satisfaction and
well-being, Performance, Activity, Communication and collaboration, and
Efficiency and flow) metrics (14.1%). In this blog we'll explore what DORA
metrics are and how to implement automated DORA metric collection using
open-source tooling running on your EKS platform.

## Understanding DORA Metrics

The DevOps Research and Assessment (DORA) team spent six years conducting
industry research to identify the metrics that best predict software delivery
performance. They distilled their findings into four key metrics that balance
velocity and stability. The first two measure how fast you deliver; the last
two measure whether you deliver reliably. Together they guard against a common
trap: optimizing for speed at the expense of stability, or vice versa.

### Velocity Metrics

**Deployment Frequency:** How often does your team release code changes to
production? High deployment frequency, when implemented correctly, accelerates
innovation through smaller and more manageable changes, provides quicker
feedback loops, and improves developer experience through a more frequent
sense of accomplishment.

**Lead Time for Changes:** How long does it take from code commit to running
successfully in production? This metric captures full pipeline efficiency:
development time, code review, testing, and deployment. It's the clearest
indicator of how much friction exists between a developer's idea and its
delivery to users.

### Stability Metrics

**Change Failure Rate (CFR):** What percentage of deployments result in
degraded service? A failed change includes system outages, service
degradation, required rollbacks, emergency patches, or immediate fixes. CFR is
calculated as `(Failed Deployments / Total Deployments) × 100`.

**Failed Deployment Recovery Time (FDRT):** How long does it take to restore
service after a failed deployment? Also known as Mean Time to Recovery (MTTR),
this metric measures the resilience of your systems and the effectiveness of
your incident response.

### Performance Benchmarks

Teams fall on the following spectrum for each metric:

| Metric                | Low performers        | Medium               | High                 | Elite                    |
|-----------------------|-----------------------|----------------------|----------------------|--------------------------|
| Deployment Frequency  | < once per 6 months   | Weekly to monthly    | Daily to weekly      | On-demand (multiple/day) |
| Lead Time for Changes | 1–6 months            | 1 week – 1 month     | 1 day – 1 week       | < 1 day                  |
| Change Failure Rate   | < 64%                 | < 15%                | < 10%                | < 5%                     |
| Recovery Time         | 1 week – 1 month      | 1 day – 1 week       | < 1 day              | < 1 hour                 |

## Why DORA Metrics Matter for Internal Developer Platforms on EKS

Amazon EKS provides the foundation for the practices that DORA metrics measure.
Kubernetes-native capabilities like declarative deployments, rolling updates,
and self-healing directly enable the behaviors that drive elite DORA
performance. But the connection goes deeper than infrastructure.

**EKS enables frequent, safe deployments.** With Kubernetes-native progressive
delivery tools like Argo Rollouts, teams can implement canary deployments,
blue-green strategies, and automated rollbacks — all of which support increased
deployment frequency while maintaining stability.

**EKS accelerates the path from code to production.** GitOps workflows using
tools like Argo CD, combined with CI/CD pipelines orchestrated by tools like
Argo Workflows, create a streamlined path from commit to production that
directly reduces lead time for changes. With the [Amazon EKS Capability for
Argo CD](https://aws.amazon.com/blogs/containers/deep-dive-simplifying-resource-orchestration-with-amazon-eks-capabilities/),
this GitOps layer is fully managed by AWS: Argo CD runs in the AWS control
plane rather than on your worker nodes, so teams get continuous deployment
without owning the upgrades, high availability, single sign-on, and
cross-cluster connectivity that self-managed Argo CD normally requires. Less
operational overhead on the delivery pipeline means teams can focus on
shipping, which is exactly what lead time for changes rewards.

**EKS enhances resilience and recovery.** Kubernetes' built-in self-healing
capabilities — automatic pod restarts, replica management, and health checks —
combined with automated rollback mechanisms, dramatically reduce recovery time
when failures occur.

**EKS provides the observability foundation.** The Kubernetes ecosystem offers
rich integration points for metric collection. Events from deployments,
rollouts, and pipeline executions can be captured and correlated to calculate
DORA metrics automatically.

The key insight is that EKS-based platforms already generate the signals
needed to measure DORA metrics. You just need the right tooling to capture and
calculate them.

<!-- CHANGED: Added the Figure 1.0 architecture image reference (was a bare
     caption in the doc). Converted the tool list to bullets. -->
## Setting Up Measurement: The Reference Architecture

Measuring DORA metrics for an Internal Developer Platform on EKS requires
connecting the events that already flow through your CI/CD and deployment
tooling into a measurement engine. Here's the reference architecture we use in
the *Platform Engineering on EKS Workshop*:

![Reference architecture for measuring platform success on Amazon EKS](images/architecture.png)

*Figure 1.0 — Reference architecture for measuring platform success for
developer platforms on Amazon EKS.*

The measurement system integrates with existing platform tools:

- **Argo Events** processes webhook events from Git repositories when code is
  pushed, pull requests are created or merged, and issues are opened or closed.
- **Argo Workflows** orchestrates measurement data collection and deployment
  event processing. Dedicated workflows track deployments, issues, and pull
  requests.
- **Argo Rollouts** validates that deployments are successful using analysis
  runs and metric-driven decisions, reporting success or failure status.
- **Apache DevLake** serves as the core measurement engine, ingesting,
  analyzing, and calculating DORA metrics using industry-standard definitions.
- **Grafana** visualizes performance trends through purpose-built DORA
  dashboards.

<!-- NEW SECTION — addresses review comments C0.1 and C1: "Prereq missing".
     Moved prerequisites out of the walkthrough into a dedicated up-front
     section modeled on the EKS Capabilities sample blog. -->
## Prerequisites

Before you start, make sure you have the following in place. This blog assumes
familiarity with Kubernetes, Helm, and GitOps concepts.

**AWS access:**

- An AWS account and a Region where you can create EKS clusters.
- AWS credentials with permission to create EKS clusters, VPCs, IAM roles, EBS
  volumes, and Elastic Load Balancers. Verify with `aws sts get-caller-identity`.

**Local tooling** (install via your package manager or the linked docs):

| Tool                    | Purpose                                | Install                                                                       |
|-------------------------|----------------------------------------|-------------------------------------------------------------------------------|
| AWS CLI v2              | Authenticate to AWS                    | https://docs.aws.amazon.com/cli/latest/userguide/getting-started-install.html |
| `eksctl`                | Create the EKS cluster                 | https://eksctl.io/installation/                                               |
| `kubectl`               | Talk to the cluster                    | https://kubernetes.io/docs/tasks/tools/                                       |
| `helm` (v3)             | Install Gitea and DevLake              | https://helm.sh/docs/intro/install/                                           |
| `kubectl-argo-rollouts` | Promote/abort the demo rollout         | `brew install argoproj/tap/kubectl-argo-rollouts`                             |
| `git`, `curl`, `jq`     | Seed the demo repo and drive webhooks  | your package manager                                                          |

**Sample code:** all the manifests and scripts referenced below live in this
directory of the [`containers-blog-maelstrom`](https://github.com/aws-samples/containers-blog-maelstrom)
repository. Clone the maelstrom repo and change into this blog's folder before
running anything:

```bash
git clone https://github.com/aws-samples/containers-blog-maelstrom.git
cd containers-blog-maelstrom/measuring-platform-success-blog
```

**Cost note:** the walkthrough creates an EKS control plane, EKS Auto Mode
compute (EC2 instances Auto Mode launches on demand), EBS volumes, and an
Elastic Load Balancer for the demo app. Run the [Teardown](#teardown) section
when you're done to avoid ongoing charges.

<!-- HEAVILY REWRITTEN — addresses review comments C0 (whole-section rework),
     C0.2/C0.3/C0.5 (narrate each step: intro sentence -> command -> output,
     less crowded, smoother flow), C0.4/C2 (code now lives in the
     containers-blog-maelstrom repo, no separate sample repo). Added a short
     framing paragraph so the section reads as the "meat" of the blog. -->
## Solution Walkthrough

The walkthrough is split into a one-shot install plus four short exercises,
one per DORA metric. Each exercise takes 3–5 minutes and drives real events
through the platform so DevLake has real data to compute against.

<!-- REWRITTEN — addresses C2 (moved code into this repo, dropped the
     aws-samples/sample-measuring-platform-success clone), C3 (consolidated the
     six install scripts into a single scripts/install-platform.sh step with
     timing), C4 (Gitea seeding broken into narrated sub-steps 1b with UI
     screenshots), C0.3 (each command now has an intro + expected output). -->
### 1. Deploy the cluster and platform

You'll bring up an EKS Auto Mode cluster, install all the platform components,
seed Gitea with the demo repository, wire DevLake and Argo Rollouts together,
and deploy the demo application. From this point on the platform records every
deployment automatically.

**1a. Create the cluster and install everything on the platform.** The
`scripts/install-platform.sh` wrapper runs six scripts (cluster,
Argo CD + kro, Argo Workflows + Argo Events, Gitea, Argo Rollouts, DevLake +
MySQL + Grafana) in order, prints a banner and duration per stage, and echoes
the next-steps prompt at the end. The whole thing takes about 25 minutes.

```bash
./scripts/install-platform.sh
```

Expected tail of the output:

```text
<< Apache DevLake + MySQL + Grafana complete in 214s

============================================================
  Platform install complete in 24m 51s
============================================================
```

If you'd rather run the stages by hand, each script is self-contained and can
be re-run safely. See `scripts/` for the individual pieces.

Before the interactive steps, open the browser-facing tunnels once with the
helper script — it starts port-forwards for Gitea, the DevLake config UI, and
Grafana in the background and prints the URL for each. (The setup scripts in
1c–1e manage their own short-lived tunnels, so this is only for the UIs you
open in a browser.)

```bash
./scripts/port-forward.sh          # start; ./scripts/port-forward.sh stop when done
```

```text
Starting port-forwards...
  Gitea                          -> http://localhost:3000  (gitea_admin / gitea_admin_pass)
  DevLake config-ui + Grafana    -> http://localhost:4000  (Grafana at /grafana)
  DevLake lake API               -> http://localhost:8080  (used by setup scripts)
```

> The DevLake config UI at `:4000` also serves Grafana under `/grafana`, so the
> DORA dashboards live at **http://localhost:4000/grafana/**. Don't port-forward
> Grafana on its own — it's pinned to serve at `/grafana` and redirects to
> `localhost:3000`, which collides with the Gitea tunnel. Log in as `admin`; the
> password is generated at install time — retrieve it with:
>
> ```bash
> kubectl -n devlake get secret devlake-grafana -o jsonpath='{.data.admin-password}' | base64 -d; echo
> ```

**1b. Seed Gitea with the demo repo.** DevLake computes *Lead Time for
Changes* by joining deployment records to Git commits, so it needs a Git
history to work from. Open the Gitea UI at http://localhost:3000 (sign in as
`gitea_admin` / `gitea_admin_pass`, set in `platform/gitea/values.yaml` —
change them for anything real) and create an empty repository called
`dora-demo` under the `gitea_admin` user.

![Creating the dora-demo repository in Gitea](images/gitea-new-repo.png)
*Figure 2 — Create an empty `dora-demo` repository in Gitea.*

Now push the `app/` folder from this blog's directory into that repository so
DevLake has commits to analyze:

```bash
# From the measuring-platform-success-blog directory:
mkdir -p /tmp/dora-demo && cp -r app/* /tmp/dora-demo/
cd /tmp/dora-demo
git init -b main
git add . && git commit -m "initial demo app"
git remote add origin http://gitea_admin:gitea_admin_pass@localhost:3000/gitea_admin/dora-demo.git
git push -u origin main
cd -   # back to measuring-platform-success-blog
```

![The dora-demo repository seeded with the app manifests](images/gitea-repo-seeded.png)
*Figure 3 — `dora-demo` after the initial push.*

**1c. Wire up DevLake.** DevLake groups everything (Gitea data + deployment
records + metric definitions) under a *project*. Script 52 creates that
project, provisions an Incoming Webhook connection, attaches it to the
project's blueprint, and stores the shared credentials in a Kubernetes secret
so the Gitea webhook workflows can reuse them. The script reaches the DevLake
lake backend on its own — if no tunnel is up it opens a temporary one for the
duration of the run — so just run it:

```bash
./scripts/52-setup-devlake-project.sh
```

Note the **connection id** the script prints (usually `1` on a fresh install);
you'll need it for the deployment-recording step below.

![The dora-demo project in the DevLake config UI](images/devlake-config-ui-project.png)
*Figure 4 — The `dora-demo` project in DevLake's config UI, with the webhook
connection attached to its blueprint.*

**1d. Register Gitea webhooks.** Script 55 applies the Argo Events
EventSource, Sensor, RBAC, and WorkflowTemplates that transform Gitea
issue/PR events into DevLake webhook records, then registers a `gitea`-type
webhook (Issues + Pull Request events) on the `dora-demo` repository. Like
script 52, it reaches Gitea on its own, opening a temporary tunnel if one
isn't already up:

```bash
./scripts/55-configure-gitea-webhooks.sh
```

![The webhook script 55 registered on the dora-demo repo](images/gitea-webhook-configured.png)
*Figure 5 — The Gitea webhook script 55 registered.*

**1e. Turn on automatic deployment recording.** Point the Argo Rollouts
controller at the same webhook connection. The poster is the controller
*inside the cluster*, so the URL uses the in-cluster config-ui DNS name — not
`localhost`. Substitute the `<connection id>` printed by script 52 (usually
`1`):

```bash
export DEVLAKE_WEBHOOK_URL="http://devlake-ui.devlake.svc.cluster.local:4000/api/rest/plugins/webhook/connections/1/deployments"
./scripts/60-configure-rollout-notifications.sh
```

From this point on, whenever a Rollout reaches **Healthy** the controller
posts a `SUCCESS` deployment; whenever a Rollout goes **Degraded** or is
aborted, it posts a `FAILURE`. You never call the webhook by hand.

**1f. Deploy the demo app.**

```bash
kubectl apply -f app/namespace.yaml
kubectl apply -f app/services.yaml
kubectl apply -f app/rollout.yaml
```

Expected output:

```text
namespace/dora-demo created
service/dora-demo created
service/dora-demo-canary created
rollout.argoproj.io/dora-demo created
```

You now have a cluster where every deploy and every Gitea issue/PR is
captured by DevLake. Throughout the exercises below, refresh the metrics on
demand with:

```bash
./scripts/70-calculate-metrics.sh
```

and view them in Grafana via the config UI tunnel from step 1a
(http://localhost:4000/grafana/, sign in as `admin` with the generated password
from the `devlake-grafana` secret, then open the DORA dashboard).

![Grafana DORA dashboard on first open, before any deploys](images/grafana-dora-overview.png)
*Figure 6 — Grafana DORA dashboard before you generate any data — every panel
is empty. That's your starting point.*

<!-- REWRITTEN — addresses C8 (prose explanation instead of "What it measures /
     Generate it" bullets), C9 (each command narrated separately), C11 (added
     expected output + Grafana screenshot placeholder). -->
### 2. Deployment Frequency

In this exercise you'll drive the first DORA metric — how often you
successfully ship to production — by shipping a version and promoting it
through the canary until it reaches `Healthy`. When the Rollout goes healthy,
Argo Rollouts posts a `SUCCESS` deployment to DevLake automatically, and the
next metrics computation counts it in Deployment Frequency.

Kick off a new version. The `ship.sh` script sets the Rollout's image and
stamps the current commit SHA so the record carries enough context for both
Deployment Frequency and Lead Time. Any image tag works
(`blue`, `green`, `red`, `orange`, `purple`, `yellow`).

```bash
./scripts/ship.sh green
```

Watch the canary progress in a second terminal. It moves 20% → 30s pause → 50%
→ manual pause → 100%:

```bash
kubectl argo rollouts get rollout dora-demo -n dora-demo --watch
```

At the 50% manual pause, promote the rollout the rest of the way:

```bash
kubectl argo rollouts promote dora-demo -n dora-demo
kubectl argo rollouts status dora-demo -n dora-demo   # blocks until Healthy
```

Expected output:

```text
rollout 'dora-demo' promoted
Status: Healthy
Updated: 1
Ready:   1
Available: 1
```

Repeat a few times with different tags to build a trend. `ship.sh` only *starts*
the rollout — the canary takes ~30s+ to reach a pause — so the loop waits until
the rollout is actually `Paused` before promoting, then uses `promote --full` to
drive it all the way to `Healthy` (a bare `promote` fired too early would skip
the timed pause and then stall at the indefinite manual gate):

```bash
for tag in blue orange purple yellow; do
  ./scripts/ship.sh "$tag"
  # wait until the rollout reaches a pause, then promote through to Healthy
  until [ "$(kubectl -n dora-demo get rollout dora-demo -o jsonpath='{.status.phase}')" = "Paused" ]; do
    sleep 3
  done
  kubectl argo rollouts promote dora-demo -n dora-demo --full
  kubectl argo rollouts status dora-demo -n dora-demo   # blocks until Healthy
done
```

Now compute the metrics and open Grafana:

```bash
./scripts/70-calculate-metrics.sh
```

The Deployment Frequency panel now shows one count per promoted rollout over
time:

![Deployment Frequency panel showing several successful deploys](images/grafana-deployment-frequency.png)
*Figure 7 — Deployment Frequency, one bar per promoted rollout.*

<!-- REWRITTEN — addresses C12 (narrative intro on what lead time shows) and
     C13 (added expected output + Grafana screenshot placeholder). -->
### 3. Lead Time for Changes

Lead Time for Changes measures how long it takes a change to go from a merged
pull request to running in production. This one is **PR-based**, so it needs a
merged PR to measure — and the mechanic that ties it together is the commit
SHA. When you merge a PR, the Gitea webhook posts a pull-request record to
DevLake carrying the PR's `createdDate`, `mergedDate`, and its **merge commit
SHA**. When you then deploy, the deployment record carries the commit SHA it
shipped. DevLake matches the deployment's SHA to the PR's merge commit SHA and
computes lead time = *deploy finished − PR opened*. The critical step is
therefore to **deploy the PR's merge commit**, not the branch tip — otherwise
the deployment and the PR never link and the panel stays empty.

So the flow is: branch → commit → open a PR → merge it → ship that merge
commit. Make sure the Gitea tunnel from step 1a is up (`http://localhost:3000`).

`scripts/ship-pr.sh` runs the whole flow in one command:

```bash
./scripts/ship-pr.sh green      # image tag is optional; defaults to green
```

Under the hood it:

1. **Branches, commits, and pushes** a change to your `dora-demo` clone.
2. **Opens a pull request** (`main` ← the new branch) and **merges it** via the
   Gitea API. Merging fires the Gitea webhook, which records the PR in DevLake
   with its `createdDate`, `mergedDate`, and **merge commit SHA**.
3. **Ships the PR's merge commit** — it reads the `merge_commit_sha` and calls
   `ship.sh green <merge_sha>`, so the deployment's commit SHA equals the PR's
   merge commit. That exact-SHA match is the link DevLake uses to compute lead
   time; shipping the branch tip instead would never link.
4. **Waits for the canary's manual pause, then promotes** to Healthy.

Recompute and check Grafana:

```bash
./scripts/70-calculate-metrics.sh
```

![Lead Time for Changes panel](images/grafana-lead-time.png)
*Figure 8 — Lead Time for Changes, median PR-merge → deploy duration.*

If Lead Time stays empty, the usual cause is a **SHA mismatch**: the deployment
was shipped with the branch-tip SHA instead of the PR's `merge_commit_sha`, so
DevLake can't link the deploy to the PR. Confirm the shipped SHA equals
`merge_commit_sha` from step 3, then re-run `70-calculate-metrics.sh`.

<!-- REWRITTEN — addresses C0.3 (narrated steps) and C14 (added expected output
     + Grafana screenshot placeholder). -->
### 4. Change Failure Rate

Change Failure Rate is the share of deployments that led to a failure in
production. The important thing to understand is **how DevLake decides a
deployment "failed": by incidents, not by the rollout's outcome.** DevLake
links incidents to deployments **by timestamp** — an incident whose creation
time falls after a deployment (and before the next one) marks *that* deployment
as a change failure. An *incident* is simply a Gitea **issue** (the webhook
records each issue as an `INCIDENT`). So `CFR = deployments followed by an
incident ÷ total deployments`, and aborting a rollout on its own doesn't move
CFR — **opening an issue after the deploy is what does.**

`scripts/ship-with-incident.sh` runs the whole pattern in one command (make
sure the Gitea tunnel from step 1a is up):

```bash
./scripts/ship-with-incident.sh red      # image tag is optional; defaults to red
```

Under the hood it:

1. **Ships and promotes** a version to Healthy — recording the deployment.
2. **Opens a Gitea issue** *after* the deploy. That fires the `issues` webhook,
   which posts the issue to DevLake as an `INCIDENT` (`type=INCIDENT`,
   `createdDate` = now). Because the incident's timestamp is later than the
   deployment's finish time, DevLake attributes it to that deployment and marks
   it a change failure.

It prints the issue number — you'll close it in section 5 for Time to Restore.
Recompute:

```bash
./scripts/70-calculate-metrics.sh
```

![Change Failure Rate panel](images/grafana-change-failure-rate.png)
*Figure 9 — Change Failure Rate = deployments followed by an incident ÷ total.*

If CFR stays flat, the incident didn't link: either no `INCIDENT`-typed issue
reached DevLake (check the `dora-incident-workflow` ran and posted), or the
issue's timestamp is before the deploy you expected it to mark. The issue must
be created **after** the deployment it represents.

<!-- REWRITTEN — addresses C0.3 (narrated steps) and C15 (added expected output
     + Grafana screenshot placeholder). NOTE: the old "Quick reference" cheat
     sheet that followed this section was removed per C16. -->
### 5. Time to Restore Service

Time to Restore Service — sometimes called Failed Deployment Recovery Time or
MTTR — measures how long it takes to recover from an incident. Just like CFR,
this metric is **incident-driven**: DevLake measures it as the span from the
incident's `createdDate` to its `resolutionDate` — i.e. from when you opened
the Gitea issue to when you close it. So this exercise picks up right where
section 4 left off: **resolve the incident you filed by closing that issue.**

First restore service by shipping the known-good version (this is the real
recovery, and records a healthy deployment):

```bash
./scripts/ship.sh green
until [ "$(kubectl -n dora-demo get rollout dora-demo -o jsonpath='{.status.phase}')" = "Paused" ]; do sleep 3; done
kubectl argo rollouts promote dora-demo -n dora-demo --full
```

Then close the incident issue from section 4 — this is what DevLake actually
measures for Time to Restore. Use the issue number that
`ship-with-incident.sh` printed (substitute it for `<N>`):

```bash
GT="http://gitea_admin:gitea_admin_pass@localhost:3000/api/v1/repos/gitea_admin/dora-demo"
curl -sS -X PATCH "$GT/issues/<N>" -H 'Content-Type: application/json' -d '{"state":"closed"}'
```

Closing fires the `issues` webhook again, which updates the incident with its
`resolutionDate` (the close time). Recompute:

```bash
./scripts/70-calculate-metrics.sh
```

![Time to Restore Service panel](images/grafana-time-to-restore.png)
*Figure 10 — Time to Restore Service, median incident open → resolved duration.*

If it stays empty, the incident was never closed (no `resolutionDate`), or the
close event didn't reach DevLake — confirm the issue shows `closed` in Gitea
and the `dora-incident-workflow` ran for the close event.

Run the fail-then-restore cycle two or three times to build a trend the panel
can plot.

<!-- NEW SECTION — addresses C18: "tear down section is missing". -->
## Teardown

When you're done, tear the environment down so it stops accruing charges.
Because the demo app provisions an Elastic Load Balancer via its Kubernetes
Service, delete the app manifests *before* the cluster so the load balancer
is released cleanly.

```bash
# 1. Remove the demo app so its load balancer is deleted first.
kubectl delete -f app/rollout.yaml   --ignore-not-found
kubectl delete -f app/services.yaml  --ignore-not-found
kubectl delete -f app/namespace.yaml --ignore-not-found

# 2. (Optional) Uninstall the Helm releases. Deleting the cluster in step 3
#    removes these anyway, but running these first speeds cluster deletion.
helm -n devlake        uninstall devlake         || true
helm -n gitea          uninstall gitea           || true
helm -n argo-rollouts  uninstall argo-rollouts   || true
helm -n argo           uninstall argo-workflows  || true
helm -n argo-events    uninstall argo-events     || true
helm -n argocd         uninstall argo-cd         || true

# 3. Delete the EKS cluster (this also deletes Auto Mode compute, node IAM
#    roles, and the VPC eksctl created).
eksctl delete cluster -f cluster/cluster.yaml --wait
```

After `eksctl` reports success, verify in the AWS console that:

- The CloudFormation stacks `eksctl-<cluster>-cluster` and any `nodegroup`
  stacks are **deleted** (not `DELETE_FAILED`).
- No orphan EBS volumes remain in the Region (tag filter `kubernetes.io/cluster/<cluster>`).
- The `dora-demo` Elastic Load Balancer is gone.
- No leftover Elastic IPs are attached to the deleted VPC.

Stop the browser tunnels from step 1a and clean up the local demo clone if you
don't need it anymore:

```bash
./scripts/port-forward.sh stop
rm -rf /tmp/dora-demo
```

<!-- REWRITTEN — addresses C17: rewrote the bulleted workshop callout as a
     single prose paragraph ("If you want to run this ... through our
     workshop"). -->
## Try It Yourself: The Platform Engineering on EKS Workshop

If you want to run this end-to-end guided by a facilitator instead of on your
own, everything in this post is available as a hands-on module in the
[Platform Engineering on EKS Workshop](https://catalog.workshops.aws/pace-eks/en-US).
The workshop walks you through building an EKS-based internal developer
platform with Backstage, Argo CD, Argo Workflows, Argo Rollouts, and Argo
Events; onboarding an application via a Backstage template that provisions a
CI/CD pipeline with automatic DORA metric collection; implementing canary
deployments with metric-driven rollback decisions; and driving each DORA
metric hands-on — pushing code, opening incident issues, closing them, and
watching all of it reflected in real-time Grafana dashboards.

## Conclusion

The data is clear: platform teams that measure their impact outperform those
that don't. But measurement shouldn't be an afterthought bolted on after the
platform is built. It should be a first-class capability of the platform
itself.

In this blog we demonstrated how DORA metrics provide the industry-standard
framework for measuring software delivery performance, and how internal
developer platforms on EKS are uniquely positioned to collect these metrics
automatically. By integrating tools like Argo Events, Argo Workflows, Apache
DevLake, and Grafana into your platform, you can establish baselines before
platform initiatives, track improvement across all four DORA dimensions over
time, and demonstrate ROI to leadership with concrete, industry-recognized
metrics — driving continuous improvement through data-driven decisions.

The most important step is the first one: start measuring. Whether you begin
with the workshop, adopt the reference architecture, or build your own
measurement pipeline, the key is to move from the roughly half of teams who
don't have clear measurement to the organizations that use data to
continuously improve their platforms. Don't be part of the group flying
blind. Your platform's value is real. Now prove it.

Interested in hands-on experience about Platform Engineering on EKS?
[Register for a guided hands-on workshop](https://catalog.workshops.aws/pace-eks/en-US).

<!-- CHANGED — addresses C19/C20/C21 (removed duplicate DORA / State of Platform
     Engineering / Apache DevLake entries, one canonical link each) and
     C1486308137 (added the EKS Capabilities deep-dive link). -->
For more information, see the following resources:

- [Platform Engineering on EKS Workshop](https://catalog.workshops.aws/pace-eks/en-US) —
  hands-on experience with DORA metrics on EKS.
- [Simplifying resource orchestration with Amazon EKS Capabilities](https://aws.amazon.com/blogs/containers/deep-dive-simplifying-resource-orchestration-with-amazon-eks-capabilities/) —
  a deep dive into the EKS Capability for Argo CD.
- [Balance Deployment Speed and Stability with DORA Metrics](https://aws.amazon.com/blogs/devops/balance-deployment-speed-and-stability-with-dora-metrics/) —
  AWS DevOps blog on DORA with CodePipeline and EventBridge.
- [Measuring IDP Success](https://docs.aws.amazon.com/prescriptive-guidance/latest/strategy-modern-cloud-operations/measuring-idp-success.html) —
  AWS Prescriptive Guidance on measuring internal developer platform success.
- [DORA — DevOps Research and Assessment](https://dora.dev/) — the four key
  metrics and the research behind them.
- [Apache DevLake](https://devlake.apache.org/) — open-source dev data
  platform for engineering metrics.

<!-- NEW SECTION — addresses C22: "Both our Author Bios are missing". -->
## About the authors

**Zach Jacobson** is a Customer Engineer at AWS focused on containers, DevOps,
and platform engineering. He works with financial services (FSI) customers to
build out AI and DevOps proofs of concept.

**Elamaran Shanmugam** is a Sr. Container Specialist Solutions Architect at
AWS. He helps AWS customers, ranging from start-ups to the largest
enterprises, run containerized workloads efficiently on Kubernetes, Amazon
EKS and Amazon ECS. He works with them on platform engineering, GitOps,
observability, and progressive delivery for containers on AWS.
