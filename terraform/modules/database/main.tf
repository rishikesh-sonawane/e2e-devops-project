# database — DynamoDB metadata table (Phase 10)
#
# The fast catalogue for every image: status (PENDING/PROCESSED/FAILED),
# original + thumbnail keys, extracted metadata (format, dimensions, SHA-256).

variable "table_name" {
  type        = string
  description = "Name of the image metadata table."
}

resource "aws_dynamodb_table" "metadata" {
  name         = var.table_name
  billing_mode = "PAY_PER_REQUEST"
  hash_key     = "image_id"

  attribute {
    name = "image_id"
    type = "S"
  }

  tags = {
    Project = "imageflow"
  }
}

output "table_name" {
  value = aws_dynamodb_table.metadata.name
}

output "table_arn" {
  value = aws_dynamodb_table.metadata.arn
}
