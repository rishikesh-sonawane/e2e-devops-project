# terraform — ImageFlow IaC (Phase 9/10)

Everything ImageFlow runs on, provisioned against the **Floci local cloud**
(`:4566`) — free, no account, no bills.

```
terraform/
├── modules/
│   ├── storage/     # S3 buckets (uploads, thumbs) + S3→Lambda notification
│   ├── database/    # DynamoDB metadata table (ImageFlowMetadata)
│   ├── messaging/   # SNS topic (imageflow-events)
│   └── compute/     # IAM role+policy, ECR repo, image-backed Lambda
└── environments/
    └── dev/         # the active environment (backend, provider, main, outputs)
```

## Workflow

```bash
# 0. One-time bootstrap (remote state on Floci — S3 + DynamoDB locking)
aws s3 mb s3://imageflow-state
aws dynamodb create-table --table-name TerraformLocks \
  --key-schema AttributeName=LockID,KeyType=HASH \
  --attribute-definitions AttributeName=LockID,AttributeType=S \
  --billing-mode PAY_PER_REQUEST

# 1. From the dev environment
cd terraform/environments/dev
terraform init        # downloads providers, wires the S3 backend
terraform plan        # review the change
terraform apply       # provision everything

# 2. Build + push the Lambda image (required before the function is usable)
./scripts/push-lambda.sh

# 3. Done — upload an image and watch the S3 trigger fire the Lambda
#    (scripts/process-pending.sh becomes an optional fallback only)
```

`deploy.sh` automates all of this (`scripts/deploy.sh` → prereqs → terraform
apply → API → smoke). `terraform destroy` tears the whole stack down.

## What gets provisioned

| Resource | Name | Notes |
|---|---|---|
| S3 bucket | `imageflow-uploads` | originals + S3 event notification → Lambda |
| S3 bucket | `imageflow-thumbs` | generated thumbnails |
| DynamoDB | `ImageFlowMetadata` | PAY_PER_REQUEST, `image_id` hash key |
| SNS | `imageflow-events` | `image.processed` announcements |
| ECR | `image-processor` | real OCI registry on `:5100` |
| Lambda | `image-processor` | `PackageType=Image`, Pillow inside, 60s timeout |
| IAM | `ImageProcessorRole` + policy | S3 r/w, DynamoDB, SNS publish |

## Notes

- **State:** stored in the `imageflow-state` S3 bucket with `TerraformLocks`
  DynamoDB locking — real remote state, all on Floci (see `backend.tf`).
  (Dummy creds are hardcoded there deliberately — ADR-02. On a real account,
  prefer `AWS_ACCESS_KEY_ID`/`AWS_SECRET_ACCESS_KEY` env vars instead.)
- **Terraform-only:** this project uses HashiCorp Terraform exclusively
  (`brew install hashicorp/tap/terraform`). No OpenTofu.
- **Image tag coupling:** `push-lambda.sh` pushes the tag from
  `IMAGEFLOW_PROCESSOR_TAG` (default `latest`) — keep it in sync with
  terraform's `processor_image_tag` variable.
- **Notification ↔ permission ordering (real AWS):** on Floci (permissive
  IAM) the S3 notification works immediately; on a real account the
  notification could be created before `aws_lambda_permission` authorizes S3
  — apply twice (or re-apply) if events are dropped on real AWS.
- **Destructive safety:** `force_destroy`/`force_delete` are set for easy
  local teardown. Flip them off (or add `prevent_destroy`) before pointing
  this at a real account — they would silently delete data.
- **Image flow:** `terraform apply` creates the *function*; the *image* comes
  from `push-lambda.sh` (build → tag → push). Apply before push creates the
  function pointing at an image that appears later — harmless for dev.
- **Trigger:** primary path is `s3` (S3 notification → Lambda, verified live).
  `direct` fallback remains: `scripts/process-pending.sh`.
