# messaging — SNS topic (Phase 10)
#
# The pipeline announces every completed image as an `image.processed`
# message on this topic (published by the image-processor Lambda).

variable "topic_name" {
  type        = string
  description = "Name of the image.processed SNS topic."
}

resource "aws_sns_topic" "events" {
  name = var.topic_name
}

output "topic_name" {
  value = aws_sns_topic.events.name
}

output "topic_arn" {
  value = aws_sns_topic.events.arn
}
