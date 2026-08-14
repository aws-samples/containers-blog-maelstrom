# The four DORA metrics (and how DevLake computes them here)

The [DORA program](https://dora.dev/) identified four key metrics that predict
software delivery performance. Two measure **throughput**, two measure
**stability**.

## Throughput

### 1. Deployment Frequency
*How often you successfully release to production.*

- **Signal in this demo:** every `SUCCESS` deployment we post to DevLake's
  Incoming Webhook when we promote the Argo Rollout.
- **DevLake computation:** counts `cicd_deployments` rows with `result = SUCCESS`
  per time bucket.

### 2. Lead Time for Changes
*How long from code committed to code running in production.*

- **Signal in this demo:** the `commitSha` attached to each deployment lets
  DevLake join the deployment back to the Gitea commit and measure the gap.
- **DevLake computation:** `deployment.finishedDate − commit.authoredDate`,
  reported as a median.

## Stability

### 3. Change Failure Rate
*What fraction of deployments cause a failure requiring remediation.*

- **Signal in this demo:** every `FAILURE` deployment we post when we **abort**
  a rollout.
- **DevLake computation:** `count(result = FAILURE) / count(all deployments)`
  in the window.

### 4. Time to Restore Service (a.k.a. Failed Deployment Recovery Time / MTTR)
*How long it takes to recover from a failure in production.*

- **Signal in this demo:** the time between a `FAILURE` deployment and the next
  `SUCCESS` deployment in the same `environment`.
- **DevLake computation:** for each failed deployment, the duration until the
  subsequent successful deployment restored the environment; reported as a
  median.

---

## The webhook payload

`scripts/record-deployment.sh` posts this shape to the DevLake webhook
`.../deployments` endpoint:

```json
{
  "deploymentCommits": [
    {
      "repoUrl": "http://gitea-http.gitea.svc.cluster.local:3000/gitea_admin/dora-demo.git",
      "refName": "main",
      "commitSha": "<sha>",
      "startedDate": "2026-07-08T20:00:00+0000",
      "finishedDate": "2026-07-08T20:02:00+0000"
    }
  ],
  "result": "SUCCESS",         // or FAILURE
  "environment": "PRODUCTION",
  "id": "dora-demo-<sha>-<finished>",
  "startedDate": "2026-07-08T20:00:00+0000",
  "finishedDate": "2026-07-08T20:02:00+0000"
}
```

- `result` drives Deployment Frequency (SUCCESS) and Change Failure Rate
  (FAILURE).
- `commitSha` + `repoUrl` drive Lead Time (joined to the collected Gitea commit).
- `environment` scopes Time to Restore Service — a FAILURE→SUCCESS pair must
  share the same environment.

> Payload fields follow the DevLake webhook plugin. If your DevLake version
> differs, check **config UI → Webhook connection → "how to use"**, which shows
> the exact `curl` for your instance, and adjust the script accordingly.

---

## Elite vs. low performers (for context)

| Metric                    | Elite            | Low               |
|---------------------------|------------------|-------------------|
| Deployment Frequency      | On-demand (many/day) | < 1 / 6 months |
| Lead Time for Changes     | < 1 day          | > 6 months        |
| Change Failure Rate       | 0–15%            | 40–70%            |
| Time to Restore Service   | < 1 hour         | > 6 months        |

Use the walkthrough in the main README to move the demo's numbers around and
watch the Grafana dashboard respond.
