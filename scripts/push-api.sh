#!/usr/bin/env bash
# shellcheck shell=bash
#
# imageflow-push-api — build + push the API image to Floci ECR.
#
# The Helm chart's Deployment pulls this image into the EKS cluster. Run
# BEFORE `helm install`/`helm upgrade`.
#
# Usage: ./scripts/push-api.sh
# Requires: Docker daemon, Floci running, aws CLI.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

TAG="${IMAGEFLOW_API_TAG:-latest}"

# Resolve the ECR repository URI via the AWS API (works on any Floci version).
REPO_URI="$(aws ecr describe-repositories --repository-names imageflow-api \
    --query 'repositories[0].repositoryUri' --output text 2>/dev/null || true)"
if [ -z "$REPO_URI" ] || [ "$REPO_URI" = "None" ]; then
    echo "[ERROR] ECR repository 'imageflow-api' not found — create it first: aws ecr create-repository --repository-name imageflow-api" >&2
    exit 1
fi

echo "[INFO] building imageflow-api image"
docker build -q -t imageflow-api:latest "$REPO_ROOT"

echo "[INFO] pushing ${REPO_URI}:${TAG}"
docker tag imageflow-api:latest "${REPO_URI}:${TAG}"
docker push "${REPO_URI}:${TAG}"

echo "[INFO] done — image at ${REPO_URI}:${TAG}"
