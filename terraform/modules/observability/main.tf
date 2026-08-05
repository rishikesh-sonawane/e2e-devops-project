# observability — CloudWatch alarms + EventBridge alerting (Phase 13)
#
# Turns the ImageFlow custom metrics (namespace `ImageFlow`, emitted by the
# API: Uploads/UploadErrors; by the Lambda: ProcessedCount/FailedCount) into
# alerts:
#
#   alarm (MetricAlarm) ──alarm_actions──▶ SNS (imageflow-events)
#   alarm state change  ──EventBridge────▶ SNS (imageflow-events)
#
# Honest Floci note (ADR-11): Floci stores metric alarms and their STATE, but
# does NOT persist `AlarmActions` (verified by probe — accepted, then dropped
# from describe-alarms). The alarm definitions below stay real-AWS-correct;
# the locally demonstrable alerting path is the EventBridge rule → SNS
# (put-rule/put-targets persist and list back on Floci), plus direct SNS
# publishing from the pipeline itself.

variable "topic_arn" {
  type        = string
  description = "SNS topic ARN that receives alarm notifications (imageflow-events)."
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Environment tag for the alarms."
}

# ── CloudWatch alarms (ImageFlow namespace) ──────────────────────────

# Any FAILED image is a pipeline health problem worth paging on — a FAILED
# status is the observable dead-letter state of the image processor.
resource "aws_cloudwatch_metric_alarm" "failed_images" {
  alarm_name          = "imageflow-failed-images"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "FailedCount"
  namespace           = "ImageFlow"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "PIPELINE HEALTH: an image failed processing (dead-letter state)."
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.topic_arn]
  tags = {
    Project     = "imageflow"
    Environment = var.environment
  }
  # Floci quirk (probe-verified): datapoints_to_alarm is accepted but not
  # persisted (returns null on refresh) while the provider defaults it to 1 —
  # ignoring keeps the plan idempotent ("No changes"). Same class as ADR-12/13.
  lifecycle {
    ignore_changes = [datapoints_to_alarm]
  }
}

# Uploads rejected with an error (503 cloud-unavailable path) — a red flag
# that the API's cloud backends are unreachable.
resource "aws_cloudwatch_metric_alarm" "upload_errors" {
  alarm_name          = "imageflow-upload-errors"
  comparison_operator = "GreaterThanThreshold"
  evaluation_periods  = "1"
  metric_name         = "UploadErrors"
  namespace           = "ImageFlow"
  period              = "300"
  statistic           = "Sum"
  threshold           = "0"
  alarm_description   = "API HEALTH: an upload was rejected with an error (cloud unavailable)."
  treat_missing_data  = "notBreaching"
  alarm_actions       = [var.topic_arn]
  tags = {
    Project     = "imageflow"
    Environment = var.environment
  }
  # Floci quirk — see failed_images (datapoints_to_alarm not persisted).
  lifecycle {
    ignore_changes = [datapoints_to_alarm]
  }
}

# ── EventBridge rule: alarm state changes → SNS ──────────────────────
# The demonstrable alerting path on Floci (put-rule + put-targets persist;
# alarm_actions do not — see header note).

resource "aws_cloudwatch_event_rule" "alarm_state_changes" {
  name        = "imageflow-alarm-events"
  description = "Forward ImageFlow CloudWatch alarm state changes to SNS."
  event_pattern = jsonencode({
    source      = ["aws.cloudwatch"]
    detail-type = ["CloudWatch Alarm State Change"]
  })
}

resource "aws_cloudwatch_event_target" "alarm_state_changes_sns" {
  rule      = aws_cloudwatch_event_rule.alarm_state_changes.name
  target_id = "imageflow-sns"
  arn       = var.topic_arn
  # NOTE (real AWS): an SNS topic targeted by EventBridge needs a resource
  # policy allowing events.amazonaws.com to Publish — add one before going
  # beyond Floci (Floci does not enforce cross-service policies).
}

output "failed_images_alarm" {
  value = aws_cloudwatch_metric_alarm.failed_images.alarm_name
}

output "upload_errors_alarm" {
  value = aws_cloudwatch_metric_alarm.upload_errors.alarm_name
}

output "alarm_events_rule" {
  value = aws_cloudwatch_event_rule.alarm_state_changes.name
}
