#!/usr/bin/env bash
# stop.sh — CodeDeploy ApplicationStop hook
# Stops and removes the previous ImageFlow API container (idempotent).

set -euo pipefail

CONTAINER="${IMAGEFLOW_CONTAINER:-imageflow-api}"

if docker ps -q --filter "name=${CONTAINER}" | grep -q .; then
    echo "[codedeploy] stopping ${CONTAINER}"
    docker rm -f "${CONTAINER}" >/dev/null
else
    echo "[codedeploy] ${CONTAINER} not running — nothing to stop"
fi
