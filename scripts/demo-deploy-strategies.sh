#!/usr/bin/env bash
# shellcheck shell=bash
#
# imageflow-demo-deploy-strategies — replay the Phase 12 deployment-strategy
# demos on the Floci EKS (k3s) cluster.
#
# Four demos, each a self-contained function:
#   1. rolling  — RollingUpdate with maxSurge 1 / maxUnavailable 0 (helm)
#   2. rollback — deliberately broken image → CrashLoop → kubectl rollout undo
#   3. canary   — v3 canary alongside stable v2, measure traffic split, promote
#   4. bluegreen— two stacks + atomic Service selector flip + flip-back
#
# Usage: ./scripts/demo-deploy-strategies.sh [rolling|rollback|canary|bluegreen|all]
# Requires: Floci running, kubectl against the k3s cluster, helm, the versioned
#           images pushed (v2, v3, broken) — see scripts/push-api.sh + the
#           "build versioned images" section of docs/deployment-strategies.md.
#
# NOTE: traffic-split measurements MUST go through the in-cluster ClusterIP
# path (kubectl exec + python3), not `kubectl port-forward` — on Floci the
# port-forward tunnel pins to a single endpoint and reports a false 100/0.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

# Matches the chart's image.repository (Floci ECR :5100 real registry).
readonly REG="000000000000.dkr.ecr.us-east-1.localhost:5100/imageflow-api"
readonly CHART="$REPO_ROOT/helm/imageflow"

# ── Logging helpers ──────────────────────────────────────────────────
info()  { printf '[INFO]  %s\n' "$*"; }
step()  { printf '\n[STEP]  %s\n' "$*"; }
error() { printf '[ERROR] %s\n' "$*" >&2; }

usage() {
    cat <<EOF
Usage: $0 [rolling|rollback|canary|bluegreen|all]

Replay the Phase 12 deployment-strategy demos on Floci EKS (k3s).

Demos:
  rolling    RollingUpdate (maxSurge 1 / maxUnavailable 0) to image v2
  rollback   deploy broken image -> CrashLoop -> rollout undo back to v2
  canary     v3 canary Deployment, measure split, promote, clean up
  bluegreen  blue(v2)/green(v3) stacks, atomic selector flip, flip back
  all        run all four demos in order

Requires: Floci running, kubectl context set, helm, versioned images pushed.
EOF
}

require_cluster() {
    kubectl get nodes >/dev/null 2>&1 || { error "kubectl cannot reach the cluster — is Floci running and the kubeconfig set?"; exit 1; }
    helm lint "$CHART" >/dev/null 2>&1 || { error "helm chart failed lint"; exit 1; }
}

# version_split <cluster_ip> <requests>  → Counter dict of git_sha responses
# Exercises the real kube-proxy path from inside a pod (port-forward lies here).
version_split() {
    local ip="$1" n="$2"
    kubectl exec deploy/imageflow -- python3 -c "
import urllib.request, collections, json
c = collections.Counter()
for _ in range($n):
    r = urllib.request.urlopen('http://$ip:8000/version', timeout=5).read().decode()
    c[json.loads(r).get('git_sha')] += 1
print(dict(c))"
}

demo_rolling() {
    step "DEMO 1/4 — ROLLING UPDATE to v2 (3 replicas, maxSurge 1 / maxUnavailable 0)"
    helm upgrade --install imageflow "$CHART" --set image.tag=v2 --set replicaCount=3 | tail -1
    kubectl rollout status deployment/imageflow --timeout=180s | tail -1
    info "pods now running:"
    kubectl get pods -l app.kubernetes.io/name=imageflow -o wide | tail -n +2 | head -6
    info "rollout history (new ReplicaSet from the v2 upgrade):"
    kubectl rollout history deployment/imageflow | tail -3
}

demo_rollback() {
    step "DEMO 2/4 — ROLLBACK (broken image -> CrashLoop -> rollout undo -> v2)"
    info "deploying deliberately BROKEN image (readiness never passes)..."
    helm upgrade --install imageflow "$CHART" --set image.tag=broken --set replicaCount=3 | tail -1
    sleep 15
    info "pod states (expect CrashLoopBackOff / not-ready on the broken RS):"
    kubectl get pods -l app.kubernetes.io/name=imageflow | tail -n +2 | head -6
    info "recovering: kubectl rollout undo ..."
    kubectl rollout undo deployment/imageflow
    kubectl rollout status deployment/imageflow --timeout=180s | tail -1
    kubectl get deploy imageflow -o jsonpath='image={.spec.template.spec.containers[0].image} ready={.status.readyReplicas}/{.status.replicas}\n'
    info "rollout history shows REVISION 1 (latest, good), 2 (broken), 3 (undo):"
    kubectl rollout history deployment/imageflow | tail -4
}

demo_canary() {
    step "DEMO 3/4 — CANARY (v3 slice alongside stable v2, measure, promote)"
    info "ensure stable has 3 replicas + visible version (so 3+3 ≈ 50/50):"
    kubectl scale deploy imageflow --replicas=3 >/dev/null
    kubectl set env deployment/imageflow GIT_SHA=v2 >/dev/null 2>&1 || true
    kubectl rollout status deployment/imageflow --timeout=120s >/dev/null 2>&1

    info "apply canary (v3, 1 replica = ~25% slice):"
    kubectl apply -f "$REPO_ROOT/k8s/demo/canary.yaml"
    kubectl rollout status deployment/imageflow-canary --timeout=120s | tail -1

    info "grow the slice to 3 replicas (~50/50):"
    kubectl scale deploy imageflow-canary --replicas=3
    kubectl rollout status deployment/imageflow-canary --timeout=120s | tail -1
    sleep 5

    local ip
    ip="$(kubectl get svc imageflow -o jsonpath='{.spec.clusterIP}')"
    info "80 in-cluster requests against ClusterIP $ip (expect ~50/50 v2/v3):"
    version_split "$ip" 80

    info "PROMOTE: stable -> v3, then delete canary:"
    kubectl set image deployment/imageflow imageflow="$REG:v3"
    kubectl rollout status deployment/imageflow --timeout=120s | tail -1
    kubectl delete deploy imageflow-canary
    info "final pods (all v3):"
    kubectl get pods -l app.kubernetes.io/name=imageflow | tail -n +2 | head -6
}

demo_bluegreen() {
    step "DEMO 4/4 — BLUE/GREEN (blue v2 live -> atomic flip to green v3 -> flip back)"
    kubectl apply -f "$REPO_ROOT/k8s/demo/blue-green.yaml"
    kubectl rollout status deploy/imageflow-blue  --timeout=120s | tail -1
    kubectl rollout status deploy/imageflow-green --timeout=120s | tail -1

    local bg_ip
    bg_ip="$(kubectl get svc imageflow-bg -o jsonpath='{.spec.clusterIP}')"

    info "Service endpoints (should be BLUE only):"
    kubectl get endpoints imageflow-bg -o jsonpath='{.subsets[0].addresses[*].targetRef.name}\n'
    info "20 requests — expect ALL v2 (blue live):"
    version_split "$bg_ip" 20

    info "ATOMIC CUTOVER — patch selector to green:"
    kubectl patch svc imageflow-bg -p '{"spec":{"selector":{"app.kubernetes.io/name":"imageflow","color":"green"}}}'
    sleep 2
    info "Service endpoints (should be GREEN only):"
    kubectl get endpoints imageflow-bg -o jsonpath='{.subsets[0].addresses[*].targetRef.name}\n'
    info "20 requests — expect ALL v3 (green live):"
    version_split "$bg_ip" 20

    info "ROLLBACK — flip the selector back to blue:"
    kubectl patch svc imageflow-bg -p '{"spec":{"selector":{"app.kubernetes.io/name":"imageflow","color":"blue"}}}'
    sleep 2
    info "20 requests — expect ALL v2 again:"
    version_split "$bg_ip" 20

    info "cleanup blue/green demo stacks:"
    kubectl delete deploy imageflow-blue imageflow-green svc imageflow-bg
}

demo_all() {
    demo_rolling
    demo_rollback
    demo_canary
    demo_bluegreen
    step "ALL DEMOS DONE — restoring chart-managed state (1 replica, tag=latest)"
    helm upgrade --install imageflow "$CHART" | tail -1
    kubectl rollout status deployment/imageflow --timeout=120s | tail -1
    info "restored:"
    kubectl get deploy,svc -l app.kubernetes.io/name=imageflow
}

main() {
    require_cluster
    case "${1:-all}" in
        rolling)   demo_rolling ;;
        rollback)  demo_rollback ;;
        canary)    demo_canary ;;
        bluegreen) demo_bluegreen ;;
        all)       demo_all ;;
        -h|--help) usage ;;
        *) error "unknown demo: $1"; usage >&2; exit 2 ;;
    esac
}

main "$@"
