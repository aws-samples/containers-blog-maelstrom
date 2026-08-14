# Screenshots to capture for the blog

The blog draft (`blog.md`) references the images below. Capture each one from a
fresh install so the reader sees exactly what they'll see. Save all files as
PNG, 1600 px wide, dark or light theme (be consistent within a section).

## Setup screenshots

| Filename                        | Where                                                                              |
|---------------------------------|------------------------------------------------------------------------------------|
| `architecture.png`              | Figure 1.0 — reference architecture diagram (export from draw.io / miro)           |
| `gitea-new-repo.png`            | Gitea UI (`http://localhost:3000`) → "+ / New Repository" filled in for `dora-demo`|
| `gitea-repo-seeded.png`         | Gitea UI → `dora-demo` repo landing page after pushing `app/`                      |
| `gitea-webhook-configured.png`  | Gitea UI → `dora-demo` → Settings → Webhooks — the webhook script 55 created       |
| `devlake-config-ui-project.png` | DevLake config-ui (`http://localhost:4000`) → Projects → `dora-demo`               |
| `devlake-blueprint-run.png`     | DevLake config-ui → Blueprints → the blueprint's last run showing `success`        |

## Grafana DORA dashboards (one per metric section)

Open `http://localhost:3001` after running `./scripts/70-calculate-metrics.sh`
and take the DORA dashboard shot for each metric panel individually.

| Filename                          | Panel                                       |
|-----------------------------------|---------------------------------------------|
| `grafana-deployment-frequency.png`| Deployment Frequency panel                  |
| `grafana-lead-time.png`           | Lead Time for Changes panel                 |
| `grafana-change-failure-rate.png` | Change Failure Rate panel                   |
| `grafana-time-to-restore.png`     | Time to Restore Service panel               |
| `grafana-dora-overview.png`       | The whole DORA dashboard, all four metrics  |

## Terminal outputs (paste into fenced blocks in the blog, no image needed)

For each metric section, capture the last ~20 lines of:

- `./scripts/ship.sh <tag>` output
- `kubectl argo rollouts get rollout dora-demo -n dora-demo` (final state)
- `./scripts/70-calculate-metrics.sh` (blueprint completion summary)
