#!/usr/bin/env bash
# deploy.sh — CodeDeploy AfterInstall hook
# Pulls the image built by CodeBuild (URI from image-uri.txt) and starts it.
#
# On Floci EC2, the docker daemon is the host daemon (the "instance" is a
# container sharing the host Docker socket), so host.docker.internal is used
# to reach Floci services (S3/DDB/SNS) exactly like the Lambda container.

set -euo pipefail

CONTAINER="${IMAGEFLOW_CONTAINER:-imageflow-api}"

# The image URI is deterministic (CodeBuild pushes ${ECR_API_URI}:latest); allow
# an explicit override via the deployment group's environment if ever needed.
IMAGE_URI="${IMAGEFLOW_IMAGE_URI:-host.docker.internal:5100/imageflow-api:latest}"
echo "[codedeploy] pulling ${IMAGE_URI}"

# Push the image into the local daemon so docker run uses it directly.
docker pull "${IMAGE_URI}"

# Start the API on the host network so it can reach Floci at localhost:4566.
docker run -d \
    --name "${CONTAINER}" \
    --network host \
    --restart unless-stopped \
    -e AWS_ENDPOINT_URL="${AWS_ENDPOINT_URL:-http://host.docker.internal:4566}" \
    -e AWS_ACCESS_KEY_ID="${AWS_ACCESS_KEY_ID:-test}" \
    -e AWS_SECRET_ACCESS_KEY="${AWS_SECRET_ACCESS_KEY:-test}" \
    -e AWS_DEFAULT_REGION="${AWS_DEFAULT_REGION:-us-east-1}" \
    "${IMAGE_URI}"

echo "[codedeploy] container ${CONTAINER} started from ${IMAGE_URI}"
