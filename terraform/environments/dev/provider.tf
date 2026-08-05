# Provider — every service talks to the local cloud (Floci :4566).
# Dummy credentials are fine (ADR-02); path-style S3 is required for
# emulated endpoints.
terraform {
  required_version = ">= 1.6"

  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    random = {
      source  = "hashicorp/random"
      version = "~> 3.0"
    }
  }
}

provider "aws" {
  region                      = var.region
  access_key                  = "test"
  secret_key                  = "test"
  skip_credentials_validation = true
  skip_metadata_api_check     = true
  skip_region_validation      = true
  s3_use_path_style           = true

  endpoints {
    s3             = var.endpoint_url
    dynamodb       = var.endpoint_url
    sns            = var.endpoint_url
    lambda         = var.endpoint_url
    iam            = var.endpoint_url
    ecr            = var.endpoint_url
    sts            = var.endpoint_url
    cloudwatch     = var.endpoint_url
    logs           = var.endpoint_url
    events         = var.endpoint_url
    kms            = var.endpoint_url
    secretsmanager = var.endpoint_url
    cognitoidp     = var.endpoint_url
    wafv2          = var.endpoint_url
    autoscaling    = var.endpoint_url
  }
}
