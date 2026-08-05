# Backend — Floci S3 remote state + DynamoDB locking (Phase 10)
#
# State lives in the `imageflow-state` bucket (key imageflow/terraform.tfstate)
# and locking in the `TerraformLocks` DynamoDB table — both on Floci, both free.
# Bootstrap once before `terraform init`:
#   aws s3 mb s3://imageflow-state
#   aws dynamodb create-table --table-name TerraformLocks \
#     --key-schema AttributeName=LockID,KeyType=HASH \
#     --attribute-definitions AttributeName=LockID,AttributeType=S \
#     --billing-mode PAY_PER_REQUEST
terraform {
  backend "s3" {
    bucket                      = "imageflow-state"
    key                         = "imageflow/terraform.tfstate"
    region                      = "us-east-1"
    access_key                  = "test"
    secret_key                  = "test"
    dynamodb_table              = "TerraformLocks"
    skip_credentials_validation = true
    skip_metadata_api_check     = true
    skip_region_validation      = true
    use_path_style              = true
    endpoints = {
      s3       = "http://localhost:4566"
      dynamodb = "http://localhost:4566"
    }
  }
}
