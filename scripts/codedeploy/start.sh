#!/usr/bin/env bash
# start.sh — CodeDeploy ApplicationStart hook
# Ensures the API container is running (deploy.sh already started it).

set -euo pipefail

CONTAINER="${IMAGEFLOW_CONTAINER:-imageflow-api}"

if ! docker ps -q --filter "name=${CONTAINER}" | grep -q .; then
    echo "[codedeploy] ERROR: ${CONTAINER} is not running" >&2
    exit 1
fi

echo "[codedeploy] ${CONTAINER} is running"
