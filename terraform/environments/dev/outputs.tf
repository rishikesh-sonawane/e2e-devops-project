output "uploads_bucket" {
  value = module.storage.uploads_bucket
}

output "thumbs_bucket" {
  value = module.storage.thumbs_bucket
}

output "metadata_table" {
  value = module.database.table_name
}

output "sns_topic" {
  value = module.messaging.topic_name
}

output "processor_function" {
  value = module.compute.function_name
}

output "processor_image" {
  value = module.compute.repository_url
}
