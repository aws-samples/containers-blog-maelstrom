# Demo app

The demo is intentionally trivial — it's just a vehicle for producing
deployment events. It uses the public `argoproj/rollouts-demo` image, which
serves its "color" (a stand-in for a version) at `/color` and a small UI at
`/` that visualizes traffic split between stable and canary during a rollout.

## Why an Argo Rollout instead of a Deployment?

A plain `Deployment` gives you a single rolling update with no natural
promote/abort gate. The `Rollout` canary strategy adds:

- **A manual pause** (`pause: {}`) at 50% weight — your promote/abort decision
  point, which is exactly the moment a DORA "deployment" succeeds or fails.
- **`abort`** — an instant rollback to the last stable ReplicaSet, which is our
  "failed change" + the start of a "time to restore" window.

## Automatic DORA recording

This Rollout is annotated to subscribe to Argo Rollouts notification triggers
(`notifications.argoproj.io/subscribe.on-deploy-success.devlake` and
`…on-deploy-failure.devlake`). When it reaches **Healthy** the controller posts
a `SUCCESS` deployment to DevLake; when it goes **Degraded/aborted** it posts a
`FAILURE`. You never call the webhook by hand — see README section 9.

The `dora.dev/commit-sha` annotation carries the shipped commit so DevLake can
compute Lead Time; `scripts/ship.sh` stamps the real value on each deploy.

## Common commands

```bash
# Watch the rollout live
kubectl argo rollouts get rollout dora-demo -n dora-demo --watch

# Ship a new version (stamps commit sha + sets image → auto-records on Healthy)
../scripts/ship.sh green

# Promote through the pause
kubectl argo rollouts promote dora-demo -n dora-demo

# Abort (roll back → auto-records FAILURE)
kubectl argo rollouts abort dora-demo -n dora-demo

# See the demo UI
kubectl -n dora-demo port-forward svc/dora-demo-stable 8090:80
# open http://localhost:8090
```

Available image tags for `argoproj/rollouts-demo`: `blue`, `green`, `yellow`,
`red`, `purple`, `orange` — each a different color so you can *see* the
rollout change.
