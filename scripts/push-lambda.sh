#!/usr/bin/env bash
# shellcheck shell=bash
#
# imageflow-push-lambda — build + push the image-processor image to Floci ECR.
#
# The Lambda runs as a custom Docker image (ADR-06). Run this BEFORE
# `terraform apply` so the image the function points at exists.
#
# Usage: ./scripts/push-lambda.sh
# Requires: Docker daemon, Floci running, aws CLI.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

TAG="${IMAGEFLOW_PROCESSOR_TAG:-latest}"

# Resolve the ECR repository URI via the AWS API (works on any Floci version).
REPO_URI="$(aws ecr describe-repositories --repository-names image-processor \
    --query 'repositories[0].repositoryUri' --output text 2>/dev/null || true)"
if [ -z "$REPO_URI" ] || [ "$REPO_URI" = "None" ]; then
    echo "[ERROR] ECR repository 'image-processor' not found — run terraform apply first (or create it: aws ecr create-repository --repository-name image-processor)" >&2
    exit 1
fi

echo "[INFO] building image-processor image"
docker build -q -t image-processor:latest "$REPO_ROOT/lambda/image-processor"

echo "[INFO] pushing ${REPO_URI}:${TAG}"
docker tag image-processor:latest "${REPO_URI}:${TAG}"
docker push "${REPO_URI}:${TAG}"

echo "[INFO] done — image at ${REPO_URI}:${TAG}"
