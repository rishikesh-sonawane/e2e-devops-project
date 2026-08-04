#!/usr/bin/env bash
# validate.sh — CodeDeploy ValidateService hook
# Health-checks the deployed API container.

set -euo pipefail

CONTAINER="${IMAGEFLOW_CONTAINER:-imageflow-api}"
PORT="${IMAGEFLOW_PORT:-8000}"
ATTEMPTS="${IMAGEFLOW_VALIDATE_ATTEMPTS:-15}"

echo "[codedeploy] waiting for /health on :${PORT}"

for _ in $(seq 1 "${ATTEMPTS}"); do
    if curl -sf --max-time 2 "http://127.0.0.1:${PORT}/health" >/dev/null 2>&1; then
        echo "[codedeploy] /health OK — deployment validated"
        exit 0
    fi
    sleep 2
done

echo "[codedeploy] ERROR: /health never became healthy" >&2
docker ps -a --filter "name=${CONTAINER}" 2>/dev/null | head -5 || true
exit 1
