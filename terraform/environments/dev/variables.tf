variable "region" {
  type    = string
  default = "us-east-1"
}

variable "endpoint_url" {
  type    = string
  default = "http://localhost:4566"
}

variable "uploads_bucket" {
  type    = string
  default = "imageflow-uploads"
}

variable "thumbs_bucket" {
  type    = string
  default = "imageflow-thumbs"
}

variable "metadata_table" {
  type    = string
  default = "ImageFlowMetadata"
}

variable "sns_topic" {
  type    = string
  default = "imageflow-events"
}

variable "processor_function_name" {
  type    = string
  default = "image-processor"
}

variable "processor_image_tag" {
  type    = string
  default = "latest"
}
