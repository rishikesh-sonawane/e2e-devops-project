# compute — IAM + ECR + image-backed Lambda (Phase 10, ADR-06)
#
# The image-processor runs as a custom Docker image (Pillow inside) pushed to
# Floci ECR (a real OCI registry on :5100). Before `terraform apply`, build
# and push the image with scripts/push-lambda.sh — then apply registers it.

variable "function_name" {
  type        = string
  description = "Name of the image-processor Lambda."
}

variable "image_tag" {
  type        = string
  default     = "latest"
  description = "ECR image tag to deploy."
}

variable "uploads_bucket" {
  type        = string
  description = "Bucket holding original uploads (for the IAM policy)."
}

variable "thumbs_bucket" {
  type        = string
  description = "Bucket holding generated thumbnails (for the IAM policy)."
}

variable "metadata_table_arn" {
  type        = string
  description = "ARN of the DynamoDB metadata table (for the IAM policy)."
}

variable "sns_topic_arn" {
  type        = string
  description = "ARN of the image.processed SNS topic (for the IAM policy)."
}

# NOTE: the AWS endpoint is intentionally NOT set as a Lambda env var.
# Floci injects the container-reachable endpoint itself; overriding it with
# the host's localhost:4566 breaks in-container connectivity (localhost inside
# the container is the container, not the host). The handler's localhost:4566
# default only applies when Floci does not inject anything.

# ── IAM ───────────────────────────────────────────────────────────────
resource "aws_iam_role" "processor" {
  name = "ImageProcessorRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect    = "Allow"
      Principal = { Service = "lambda.amazonaws.com" }
      Action    = "sts:AssumeRole"
    }]
  })
}

resource "aws_iam_policy" "processor" {
  name = "ImageProcessorPolicy"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "S3ReadWrite"
        Effect = "Allow"
        Action = [
          "s3:GetObject",
          "s3:PutObject",
          "s3:ListBucket",
        ]
        Resource = [
          "arn:aws:s3:::${var.uploads_bucket}",
          "arn:aws:s3:::${var.uploads_bucket}/*",
          "arn:aws:s3:::${var.thumbs_bucket}",
          "arn:aws:s3:::${var.thumbs_bucket}/*",
        ]
      },
      {
        Sid    = "DynamoDBReadWrite"
        Effect = "Allow"
        Action = [
          "dynamodb:GetItem",
          "dynamodb:PutItem",
          "dynamodb:Scan",
          "dynamodb:UpdateItem",
        ]
        Resource = var.metadata_table_arn
      },
      {
        Sid      = "SNSPublish"
        Effect   = "Allow"
        Action   = ["sns:Publish"]
        Resource = var.sns_topic_arn
      },
      # CreateTopic cannot be scoped to a pre-existing ARN (the topic is created
      # by name), so it needs the wildcard — Publish above stays tight.
      {
        Sid      = "SNSCreateTopic"
        Effect   = "Allow"
        Action   = ["sns:CreateTopic"]
        Resource = ["*"]
      },
      # Least privilege (Phase 14): CreateLogGroup cannot be ARN-scoped, but
      # CreateLogStream/PutLogEvents are scoped to this function's log group.
      {
        Sid      = "CloudWatchLogs"
        Effect   = "Allow"
        Action   = ["logs:CreateLogGroup"]
        Resource = ["*"]
      },
      {
        Sid      = "CloudWatchLogStream"
        Effect   = "Allow"
        Action   = ["logs:CreateLogStream", "logs:PutLogEvents"]
        Resource = ["arn:aws:logs:*:*:log-group:/aws/lambda/${var.function_name}:*"]
      },
      # Phase 13: the Lambda emits ProcessedCount/FailedCount. PutMetricData
      # is namespace-scoped, not ARN-scoped — the wildcard is the AWS-correct
      # shape (real AWS docs: put_metric_data requires Resource: "*").
      {
        Sid      = "CloudWatchPutMetrics"
        Effect   = "Allow"
        Action   = ["cloudwatch:PutMetricData"]
        Resource = ["*"]
      },
    ]
  })
}

resource "aws_iam_role_policy_attachment" "processor" {
  role       = aws_iam_role.processor.name
  policy_arn = aws_iam_policy.processor.arn
}

# ── ECR (image store) ─────────────────────────────────────────────────
resource "aws_ecr_repository" "processor" {
  name                 = var.function_name
  image_tag_mutability = "MUTABLE"
  force_delete         = true
}

# ── Lambda (image-backed, ADR-06) ────────────────────────────────────
resource "aws_lambda_function" "processor" {
  function_name = var.function_name
  role          = aws_iam_role.processor.arn
  package_type  = "Image"
  image_uri     = "${aws_ecr_repository.processor.repository_url}:${var.image_tag}"
  timeout       = 60
  memory_size   = 512

  # Entrypoint comes from the image's Dockerfile CMD (handler.lambda_handler).
  image_config {
    command = []
  }

  environment {
    variables = {
      IMAGEFLOW_UPLOADS_BUCKET = var.uploads_bucket
      IMAGEFLOW_THUMBS_BUCKET  = var.thumbs_bucket
      IMAGEFLOW_METADATA_TABLE = "ImageFlowMetadata"
      IMAGEFLOW_SNS_TOPIC      = "imageflow-events"
      IMAGE_PROCESSING_TRIGGER = "s3"
    }
  }

  depends_on = [aws_iam_role_policy_attachment.processor]
}

# Allow S3 to invoke the function (the notification's IAM counterpart).
resource "aws_lambda_permission" "s3_invoke" {
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.processor.function_name
  principal     = "s3.amazonaws.com"
  source_arn    = "arn:aws:s3:::${var.uploads_bucket}"
}

output "function_name" {
  value = aws_lambda_function.processor.function_name
}

output "function_arn" {
  value = aws_lambda_function.processor.arn
}

output "repository_url" {
  value = aws_ecr_repository.processor.repository_url
}
