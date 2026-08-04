#!/usr/bin/env bash
# shellcheck shell=bash
#
# imageflow-process-pending — direct-mode trigger for the image-processor
# Lambda (IMAGE_PROCESSING_TRIGGER=direct, ADR-07 fallback B).
#
# Scans DynamoDB for PENDING records and processes each one: thumbnail +
# metadata extraction → status=PROCESSED + SNS image.processed event. Used
# when Floci cannot wire S3 event notifications → Lambda.
#
# Usage: ./scripts/process-pending.sh
# Requires: Floci running, venv with app/requirements.txt +
#           lambda/image-processor/requirements.txt installed.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
readonly REPO_ROOT

if [ ! -x "$REPO_ROOT/.venv/bin/python" ]; then
    echo "[ERROR] venv not found at .venv — create it first (docs/setup.md)" >&2
    exit 1
fi

cd "$REPO_ROOT"
.venv/bin/python - <<'PY'
import sys

sys.path.insert(0, "lambda/image-processor")

import handler  # noqa: E402

count = handler.process_pending()
print(f"process-pending: {count} PENDING image(s) → PROCESSED")
PY
