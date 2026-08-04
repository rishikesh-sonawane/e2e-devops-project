# lambda/image-processor

The **process** step of the ImageFlow pipeline (ADR-01, ADR-06): a standalone
Lambda that turns a stored `PENDING` image into a processed one.

## What it does

1. Reads the original from S3 (`imageflow-uploads`, `uploads/` prefix).
2. Pillow: extracts metadata — format, mode, width, height, **SHA-256**.
3. Generates a **256px aspect-preserving thumbnail** → `imageflow-thumbs` (`thumbs/` prefix).
4. Updates the DynamoDB record: `status=PENDING → PROCESSED` + metadata + thumbnail key.
5. Publishes an **`image.processed`** event to the SNS topic `imageflow-events`.

Failure is first-class: undecodable images, missing S3 objects, or missing keys
mark the record `FAILED` with an `error` field — never silently stuck `PENDING`.

## Trigger paths (ADR-07, `IMAGE_PROCESSING_TRIGGER`)

| Path | Entry point | Notes |
|---|---|---|
| `s3` (primary) | `handler.lambda_handler(event, context)` | Parses an `s3:ObjectCreated:*` event; classic event-driven serverless |
| `direct` (fallback B) | `handler.process_pending()` | Scans DynamoDB for `PENDING` records and processes each — used when Floci can't wire S3 → Lambda |
| `dynamodb` (planned) | — | Event source mapping from DynamoDB Streams |

## Run it locally (direct trigger)

```bash
floci start && eval $(floci env)
source .venv/bin/activate && pip install -r app/requirements.txt -r lambda/image-processor/requirements.txt
uvicorn app.main:app          # terminal 1 — upload some images
./scripts/process-pending.sh  # terminal 2 — process every PENDING image
```

## Tests

```bash
python -m pytest lambda/image-processor/tests -v     # unit (offline fakes) + live (Floci, auto-skip)
```

## Packaging (ADR-06)

Custom Docker image so Pillow ships inside the function:

```bash
docker build -t image-processor lambda/image-processor
# Phase 10: push to Floci ECR and register with
# aws lambda create-function --package-type Image --image-uri ...
```

See `docs/architecture.md` §3.2 and ADR-06/07.
