# security — encryption keys, secrets, identity, and WAF (Phase 14)
#
# Provisions the Phase 14 security surface on Floci:
#   - KMS symmetric key + alias (encryption at rest for secrets)
#   - Secrets Manager secret container (the app may source AWS creds from it)
#   - Cognito user pool + app client + demo user (identity / JWT auth)
#   - WAF v2 web ACL (rate limiting + AWS-managed rules)
#   - least-privilege IAM demo user (scoped to one bucket)
#
# Honest Floci note (ADR-12): Floci validates SigV4 signatures but does NOT
# enforce IAM authorization (probe-verified — a user with a one-bucket policy
# could still ListBuckets). All resources below are real-AWS-correct; the
# IAM enforcement story is a design/audit exercise locally, a live control on
# a real account. Secrets hold values provisioned by scripts/security.sh, not
# by Terraform (never commit secret values).

variable "environment" {
  type        = string
  default     = "dev"
  description = "Environment tag for security resources."
}

variable "uploads_bucket" {
  type        = string
  description = "Bucket the least-privilege demo user may read (for the scoped policy)."
}

variable "cognito_domain_prefix" {
  type        = string
  default     = "imageflow-auth"
  description = "Cognito app client domain prefix."
}

# Demo user's temporary password is GENERATED (never a literal in the repo —
# a security audit would flag it). It lands in Terraform state, which is fine
# for the local Floci environment; real deployments use the admin invite flow.
resource "random_password" "cognito_demo" {
  length           = 16
  special          = true
  override_special = "!#$%&*?@"
  min_upper        = 1
  min_lower        = 1
  min_numeric      = 1
  min_special      = 1
}

# ── KMS (encryption key) ─────────────────────────────────────────────
resource "aws_kms_key" "app" {
  description             = "ImageFlow application encryption key (Phase 14)"
  deletion_window_in_days = 7
  enable_key_rotation     = true
  tags = {
    Project     = "imageflow"
    Environment = var.environment
  }
}

resource "aws_kms_alias" "app" {
  name          = "alias/imageflow-app-key"
  target_key_id = aws_kms_key.app.id
}

# ── Secrets Manager (secret container) ───────────────────────────────
resource "aws_secretsmanager_secret" "app" {
  name        = "imageflow/app-secret"
  description = "ImageFlow application secret (provisioned by scripts/security.sh)."
  kms_key_id  = aws_kms_key.app.arn
  tags = {
    Project     = "imageflow"
    Environment = var.environment
  }
}

# ── Cognito (identity) ───────────────────────────────────────────────
resource "aws_cognito_user_pool" "app" {
  name = "imageflow-users"
  password_policy {
    minimum_length    = 8
    require_lowercase = true
    require_numbers   = true
    require_symbols   = true
    require_uppercase = true
  }
  auto_verified_attributes = ["email"]
  tags = {
    Project     = "imageflow"
    Environment = var.environment
  }
}

resource "aws_cognito_user_pool_client" "app" {
  name                = "imageflow-app-client"
  user_pool_id        = aws_cognito_user_pool.app.id
  generate_secret     = false
  explicit_auth_flows = ["ALLOW_ADMIN_USER_PASSWORD_AUTH", "ALLOW_USER_PASSWORD_AUTH"]
}

resource "aws_cognito_user" "demo" {
  user_pool_id       = aws_cognito_user_pool.app.id
  username           = "imageflow-demo"
  temporary_password = random_password.cognito_demo.result
  message_action     = "SUPPRESS"
}

# ── WAF v2 (edge protection) ─────────────────────────────────────────
resource "aws_wafv2_web_acl" "app" {
  name        = "imageflow-web-acl"
  description = "Rate limiting + managed rules for the ImageFlow API."
  scope       = "REGIONAL"

  default_action {
    allow {}
  }

  # Rate-based rule: >100 requests/5min from one IP → block.
  rule {
    name     = "rate-limit"
    priority = 1
    action {
      block {}
    }
    statement {
      rate_based_statement {
        limit              = 100
        aggregate_key_type = "IP"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "imageflowRateLimit"
      sampled_requests_enabled   = true
    }
  }

  # AWS-managed rule set: core OWASP protection.
  rule {
    name     = "aws-managed-common"
    priority = 2
    override_action {
      none {}
    }
    statement {
      managed_rule_group_statement {
        name        = "AWSManagedRulesCommonRuleSet"
        vendor_name = "AWS"
      }
    }
    visibility_config {
      cloudwatch_metrics_enabled = true
      metric_name                = "imageflowManagedRules"
      sampled_requests_enabled   = true
    }
  }

  visibility_config {
    cloudwatch_metrics_enabled = true
    metric_name                = "imageflowWebAcl"
    sampled_requests_enabled   = true
  }

  tags = {
    Project     = "imageflow"
    Environment = var.environment
  }
}

# ── IAM (least-privilege demo) ───────────────────────────────────────
resource "aws_iam_user" "demo" {
  name = "imageflow-reader"
  tags = {
    Project     = "imageflow"
    Environment = var.environment
  }
}

# Scoped to a single bucket — the demo of least privilege (see module note
# about Floci not enforcing authorization).
resource "aws_iam_user_policy" "demo" {
  name = "read-uploads-only"
  user = aws_iam_user.demo.name

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [{
      Effect = "Allow"
      Action = ["s3:GetObject", "s3:ListBucket"]
      Resource = [
        "arn:aws:s3:::${var.uploads_bucket}",
        "arn:aws:s3:::${var.uploads_bucket}/*",
      ]
    }]
  })
}

# ── Outputs ──────────────────────────────────────────────────────────
output "kms_key_arn" {
  value = aws_kms_key.app.arn
}

output "kms_key_alias" {
  value = aws_kms_alias.app.name
}

output "secret_name" {
  value = aws_secretsmanager_secret.app.name
}

output "cognito_pool_id" {
  value = aws_cognito_user_pool.app.id
}

output "cognito_client_id" {
  value = aws_cognito_user_pool_client.app.id
}

output "waf_acl_arn" {
  value = aws_wafv2_web_acl.app.arn
}

output "iam_user" {
  value = aws_iam_user.demo.name
}
