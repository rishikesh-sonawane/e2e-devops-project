# storage — S3 buckets + event notification (Phase 10)
#
# Two buckets: originals (`uploads`) and generated thumbnails (`thumbs`).
# The uploads bucket carries an s3:ObjectCreated:* notification that hands
# each new object to the image-processor Lambda (the pipeline's trigger).

variable "uploads_bucket" {
  type        = string
  description = "Bucket for original image uploads."
}

variable "thumbs_bucket" {
  type        = string
  description = "Bucket for generated thumbnails."
}

variable "processor_function_arn" {
  type        = string
  description = "ARN of the image-processor Lambda to notify on new uploads."
}

resource "aws_s3_bucket" "uploads" {
  bucket        = var.uploads_bucket
  force_destroy = true
}

resource "aws_s3_bucket" "thumbs" {
  bucket        = var.thumbs_bucket
  force_destroy = true
}

# S3 → Lambda event notification: the primary trigger (ADR-07, s3).
resource "aws_s3_bucket_notification" "uploads_to_processor" {
  bucket = aws_s3_bucket.uploads.id

  lambda_function {
    lambda_function_arn = var.processor_function_arn
    events              = ["s3:ObjectCreated:*"]
    filter_prefix       = "uploads/"
  }

  depends_on = [aws_s3_bucket.uploads]
}

output "uploads_bucket" {
  value = aws_s3_bucket.uploads.id
}

output "thumbs_bucket" {
  value = aws_s3_bucket.thumbs.id
}
