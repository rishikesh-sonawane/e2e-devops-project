# ImageFlow — dev environment (Floci local cloud)
#
# The canonical provisioning path (replaces the app's lazy in-app
# provisioning): storage → database → messaging → compute.

module "storage" {
  source                 = "../../modules/storage"
  uploads_bucket         = var.uploads_bucket
  thumbs_bucket          = var.thumbs_bucket
  processor_function_arn = module.compute.function_arn
}

module "database" {
  source     = "../../modules/database"
  table_name = var.metadata_table
}

module "messaging" {
  source     = "../../modules/messaging"
  topic_name = var.sns_topic
}

module "compute" {
  source             = "../../modules/compute"
  function_name      = var.processor_function_name
  image_tag          = var.processor_image_tag
  uploads_bucket     = var.uploads_bucket
  thumbs_bucket      = var.thumbs_bucket
  metadata_table_arn = module.database.table_arn
  sns_topic_arn      = module.messaging.topic_arn
}

# Observability (Phase 13): CloudWatch alarms + EventBridge → SNS alerting
# on the ImageFlow custom metrics (Uploads/UploadErrors from the API,
# ProcessedCount/FailedCount from the Lambda).
module "observability" {
  source      = "../../modules/observability"
  topic_arn   = module.messaging.topic_arn
  environment = var.environment
}

# The notification depends on the Lambda existing (module graph handles it),
# but storage's notification references compute's arn — fine as-is.
