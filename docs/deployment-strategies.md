# Deployment Strategies — Phase 12

**Goal:** show *how* new versions ship to production safely — and how you recover
when they don't. Four classic strategies were demonstrated **live** on the real
Floci EKS (k3s) cluster with the ImageFlow API, using versioned images
(`v2` / `v3` / `broken`) that expose their version via `GIT_SHA` in `GET /version`.

> Replay everything: `./scripts/demo-deploy-strategies.sh` (each demo is a
> self-contained function). Manifests live in `k8s/demo/`.

---

## 0. The cast

| Image tag | What it is |
|---|---|
| `latest` | production baseline (Phase 11) |
| `v2` | new release — "current" during demos (visible via `GIT_SHA=v2`) |
| `v3` | the *next* release — target of canary + blue/green |
| `broken` | intentionally bad image — exits 1 after 2s → readiness never passes |

### Build the versioned images first (one-time)

The demos need `v2`, `v3` and `broken` tags in the Floci ECR registry
(`:5100`). The API image reads `GIT_SHA` from env — but we also bake it in at
build time so the tag is visible even before any `kubectl set env`:

```bash
REG=000000000000.dkr.ecr.us-east-1.localhost:5100/imageflow-api

# v2 and v3 — real builds with a baked-in version marker
docker build --build-arg GIT_SHA=v2 -t ${REG}:v2 .
docker push ${REG}:v2
docker build --build-arg GIT_SHA=v3 -t ${REG}:v3 .
docker push ${REG}:v3

# broken — a container that dies 2s after start, so readiness never passes
docker build -t ${REG}:broken - <<'EOF'
FROM ${REG}:latest
CMD ["/bin/sh", "-c", "echo broken-image; sleep 2; exit 1"]
EOF
docker push ${REG}:broken
```

> `broken` is the only "bad" image; it never serves traffic because the
> readiness probe never goes green. That is exactly why the rollback demo is
> safe to run on the live cluster.

The Helm chart now ships an explicit strategy (previously the Kubernetes
default, silently):

```yaml
strategy:
  type: RollingUpdate
  rollingUpdate:
    maxSurge: 1          # bring up 1 new pod BEFORE taking any old pod down
    maxUnavailable: 0    # never drop below desired replica count → zero downtime
```

---

## 1. Rolling Update — live

**Strategy:** incrementally replace old pods with new ones, keeping the
service available the whole time.

```bash
helm upgrade --install imageflow ./helm/imageflow \
  --set image.tag=v2 --set replicaCount=3
kubectl rollout status deployment/imageflow
```

**What happened (observed):** the new ReplicaSet came up, pods were replaced
incrementally, and the rollout completed. New RS: `6c49c9954d`, all 3 pods on
v2, no window where the Service had zero ready endpoints.

**Progressive delivery point:** `maxSurge: 1` / `maxUnavailable: 0` is the
"zero-downtime, never-below-3" profile — the exact kind of constraint a
production SRE would require.

---

## 2. Rollback — live

**Strategy:** when a release is bad, revert to the last known-good revision.
Kubernetes keeps rollout history; `rollout undo` restores it.

```bash
# Deploy something broken on purpose
helm upgrade --install imageflow ./helm/imageflow --set image.tag=broken
sleep 15
kubectl get pods -l app.kubernetes.io/name=imageflow   # new pods CrashLoopBackOff

# Recover
kubectl rollout undo deployment/imageflow
kubectl rollout status deployment/imageflow
```

**What happened (observed):** the broken image entered `CrashLoopBackOff` on
the new ReplicaSet. Because `maxUnavailable: 0` kept the old v2 pods running,
the Service never lost health. `rollout undo` restored **3/3 on v2** in under
two minutes. `kubectl rollout history` shows the trail: **REVISION 1** = the
good v2 rollout, **REVISION 2** = the broken attempt (stays in history),
**REVISION 3** = the revision that `undo` *creates* by copying REVISION 1 back
— undo never rewrites history, it appends a new good revision.

**Rollback is the safety net under every other strategy** — blue/green's
"flip back" is just an instant, cheaper rollback.

---

## 3. Canary — live

**Strategy:** ship the new version to a *small slice* of traffic first, measure,
then promote (or abandon). Traffic share ∝ replica count.

```bash
kubectl apply -f k8s/demo/canary.yaml        # canary v3, 1 replica
kubectl scale deploy imageflow-canary --replicas=3   # grow the slice
# promote:
kubectl set image deployment/imageflow imageflow=…:v3
kubectl delete deploy imageflow-canary
```

**What happened (observed):** with 3 stable (v2) + 3 canary (v3) pods, **80
in-cluster requests → 38× v3 / 42× v2** — a genuine ~50/50 split through the
real Service/kube-proxy path. Promoting the stable Deployment to v3 and
deleting the canary completed the release; the SAME manifest is the template
for a "abandon" path (scale canary to 0).

**Hard-won gotcha (interview gold):** `kubectl port-forward` to a *Service* on
Floci pins every connection to one endpoint — 20/20 went to v2 and looked like
a broken canary. Measuring **inside the cluster against the ClusterIP**
exercised the real kube-proxy load balancer and showed the correct split.
*Always verify traffic steering through the real data path, not a tunnel.*

---

## 4. Blue/Green — live

**Strategy:** run two complete stacks (blue + green). One serves all traffic;
the switch is a single atomic change to the Service selector. Old stack stays
warm for instant rollback.

```bash
kubectl apply -f k8s/demo/blue-green.yaml     # blue=v2, green=v3, svc→blue
# cutover:
kubectl patch svc imageflow-bg -p \
  '{"spec":{"selector":{"app.kubernetes.io/name":"imageflow","color":"green"}}}'
# rollback = patch the selector back to "blue"
```

**What happened (observed):**
- Before flip: endpoints = blue pods only; 20/20 requests → `v2`.
- After atomic flip: endpoints = green pods only; 20/20 requests → `v3`.
- Flipped back (rollback): 20/20 → `v2` again.

**Progressive delivery point:** zero downtime (old stack keeps running),
instant cutover, and the *cheapest rollback in the book* — one `kubectl patch`.

---

## 5. The honest Floci caveat (CodeDeploy)

Phase 8's inner loop uses CodeDeploy with `autoRollbackConfiguration` enabled
on the `imageflow-onprem` group. But on Floci, the **CodeDeploy lifecycle is
simulated** — there is no real agent on the instance running the appspec hooks
(`stop`/`deploy`/`start`/`validate`), so a deployment reports `Succeeded`
without executing them. Floci also resolves deployment targets via
**on-premises registration**, not EC2 tag filters (EC2-tag groups →
`NoInstancesReachable`).

**Consequence:** a *meaningful* blue/green or canary via CodeDeploy with real
traffic shifting is **not fully demonstrable on Floci**. The strategies above
are proven on the **real k3s cluster**, where Kubernetes genuinely executes
them (verifiable with `kubectl`). The appspec hooks + CodeDeploy config remain
real-AWS-correct — documented in ADR-10 — but execution is a cloud/AWS or
real-host exercise.

---

## 6. Which strategy when? (the interview answer)

| Strategy | Risk | Downtime | Rollback speed | Best for |
|---|---|---|---|---|
| Rolling | Low | None | Fast (undo) | default daily releases |
| Rollback (undo) | — | None | Seconds–minutes | any broken release |
| Canary | Lowest | None | Abandon slice | risky changes, metrics-driven gating |
| Blue/Green | Low | None | Instant (selector flip) | big jumps, easy audit of both versions |

Progressive delivery = using these together: canary to validate, rolling to
ship, blue/green for big cutovers, rollback for everything when things go wrong.
