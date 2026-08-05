# Monitoring & Observability — Phase 13

**Goal:** prove you can *see* what the pipeline is doing — metrics, logs, and
alerts — using the same AWS-native tools a production platform would use:
Prometheus-format metrics, CloudWatch custom metrics + logs, and
CloudWatch Alarms → EventBridge → SNS alerting. Everything runs locally on
Floci for $0.

> Replay everything: start Floci, `terraform apply` (provisions the alarms +
> EventBridge rule), run the API + Lambda, upload an image, then inspect with
> `./scripts/observability.sh`.

---

## 0. The three observability planes

| Plane | Tool | Who emits | Where it lands |
|---|---|---|---|
| **App metrics** | Prometheus `/metrics` (exposition format) | FastAPI process | `GET /metrics` on the API |
| **Custom metrics** | CloudWatch `put_metric_data` | API + Lambda | namespace `ImageFlow` |
| **Logs** | CloudWatch Logs | API (optional handler) | log group `/imageflow/api` |
| **Alerts** | CloudWatch Alarms → EventBridge → SNS | Terraform provisioned | topic `imageflow-events` |

Design rule (**ADR-11**): *observability must never break the pipeline.* Every
metric/log emission is wrapped — a CloudWatch outage degrades telemetry, never
image processing.

---

## 1. Prometheus `/metrics` (application level)

The API exposes Prometheus-format metrics at `GET /metrics`
(`prometheus_client`). These measure what *this process* does — the golden
signals for the request path:

| Metric | Type | Meaning |
|---|---|---|
| `imageflow_http_requests_total{method,path}` | Counter | HTTP requests handled |
| `imageflow_uploads_total` | Counter | Images accepted (S3 + DynamoDB write OK) |
| `imageflow_upload_errors_total` | Counter | Uploads rejected (cloud-unavailable 503) |
| `imageflow_upload_duration_seconds` | Histogram | Time to persist an upload |
| `imageflow_uptime_seconds` | Gauge | Process uptime |

```bash
curl -s localhost:8000/metrics | grep imageflow
```

Interview point: the histogram is the latency SLI; the error counter feeds the
availability SLI; uptime feeds the "is it running" check. In production you
would scrape this with Prometheus and alert on SLO burn rate.

## 2. CloudWatch custom metrics (system level)

The same facts, pushed into CloudWatch so they are *alarmable* and queryable
through AWS-native tooling (get-metric-statistics, list-metrics):

| Metric | Emitter | Meaning |
|---|---|---|
| `ImageFlow.Uploads` | API (`app/services/observability.py`) | Uploads accepted |
| `ImageFlow.UploadErrors` | API | Uploads rejected with an error |
| `ImageFlow.ProcessedCount` | Lambda (`lambda/image-processor/handler.py`) | Images processed OK |
| `ImageFlow.FailedCount` | Lambda | Images failed (dead-letter state) |

The split is deliberate: the API owns *ingestion* facts, the Lambda owns
*outcome* facts — each component reports only what it can observe truthfully.

```bash
# what datapoints exist?
aws cloudwatch list-metrics --namespace ImageFlow
# sum of processed images in the last hour
aws cloudwatch get-metric-statistics --namespace ImageFlow \
  --metric-name ProcessedCount --statistics Sum --period 300 \
  --start-time "$(date -u -v-1H '+%Y-%m-%dT%H:%M:%SZ')" \
  --end-time "$(date -u '+%Y-%m-%dT%H:%M:%SZ')"
```

## 3. CloudWatch Logs (optional)

API log lines go to stdout by default (the container/process captures them).
Optionally, set `CLOUDWATCH_LOGS_ENABLED=true` and the API attaches a
`logging.Handler` (`app/services/observability.py::CloudWatchLogHandler`) that
ships the same lines to the CloudWatch log group `/imageflow/api`:

```bash
CLOUDWATCH_LOGS_ENABLED=true uvicorn app.main:app --port 8000
aws logs filter-log-events --log-group-name /imageflow/api
```

## 4. Alerting — CloudWatch Alarms → EventBridge → SNS

Terraform's `observability` module provisions:

- **`imageflow-failed-images`** — `FailedCount ≥ 1` in a 300s window → SNS.
  A FAILED image is the pipeline's observable dead-letter state (the processor
  marks undecodable/missing images FAILED rather than silently dropping them).
- **`imageflow-upload-errors`** — `UploadErrors ≥ 1` → SNS. A red flag that
  the API's cloud backends are unreachable.
- **`imageflow-alarm-events`** EventBridge rule — matches
  `source: aws.cloudwatch` + `detail-type: CloudWatch Alarm State Change`,
  forwards every alarm transition to the SNS topic.

```bash
terraform -chdir terraform/environments/dev apply
aws cloudwatch describe-alarms                    # both alarms, state OK/INSUFFICIENT_DATA
aws events list-rules                             # imageflow-alarm-events ENABLED
```

**Honest Floci finding (ADR-11):** Floci stores metric alarms and their state,
but does **not persist `AlarmActions`** (probe-verified: accepted by
`put-metric-alarm`, absent from `describe-alarms`). The alarm definitions stay
real-AWS-correct (they will fire SNS on a real account); the *locally
demonstrable* alerting path is the EventBridge rule → SNS (persists and lists
back) plus the pipeline's own direct SNS publishes (`image.processed`).

## 5. The observability script

`./scripts/observability.sh` is a one-shot status report (Phase 4 contract —
exit 0/1/2, `--help`, env overrides):

```bash
./scripts/observability.sh                 # metrics + alarms + rules + logs + topics
./scripts/observability.sh --hours 6       # bigger statistics window
```

Core sections (metrics, alarms) fail the script when Floci/aws is unreachable;
informational sections (EventBridge rules, log events, SNS topics) degrade
gracefully. Behavior tests: `./scripts/tests/test_observability.sh` (a fake
`aws` CLI on PATH makes them deterministic — no Floci required).

## 6. SLIs / SLOs (the interview answer)

| SLI | Source | Proposed SLO (demo framing) |
|---|---|---|
| Availability | `1 − upload_errors_total / uploads_total` | 99.9% per month |
| Latency | `imageflow_upload_duration_seconds` (p95) | < 1s |
| Throughput | `Uploads` / `ProcessedCount` sum | track, alarm on collapse |
| Processing success | `ProcessedCount / (ProcessedCount + FailedCount)` | 99.5% |

The alarms above are the "error budget burn" tripwires: any FAILED image or
upload error fires immediately — tighter than a monthly SLO, which is exactly
how you'd wire production alerting on top of SLOs.

## 7. Demo runbook (5 minutes)

1. `floci start && eval $(floci env)` (or verify `floci doctor`).
2. `terraform -chdir terraform/environments/dev apply` — provisions the two
   alarms + EventBridge rule.
3. `./scripts/push-lambda.sh && terraform apply` (image-backed Lambda with
   metric emission) — or rely on the existing deployed function.
4. `source .venv/bin/activate && uvicorn app.main:app --port 8000 &`
5. Upload: `curl -X POST -F "file=@some.png" localhost:8000/api/v1/images`
6. `./scripts/observability.sh` — watch `Uploads` and `ProcessedCount`
   datapoints appear; alarms report `OK`/`INSUFFICIENT_DATA`.
7. Failure demo: upload a non-image (`.txt` with junk bytes) → the Lambda
   marks it FAILED → `ImageFlow.FailedCount` gets a datapoint →
   `imageflow-failed-images` moves toward ALARM → the EventBridge rule would
   push an SNS message on a real account.

## 8. What Phase 13 deliberately excludes

- **OpenSearch**: Floci runs a real OpenSearch engine, but it is a heavyweight
  container; the CloudWatch-only stack covers the same story (metrics + logs +
  alerts) in-process and fast. OpenSearch remains a roadmap extension (ADR-11).
- **Grafana/Prometheus server**: the API exports Prometheus format; wiring a
  scraper + dashboards is an optional extension, not required to demonstrate
  the observability story.
