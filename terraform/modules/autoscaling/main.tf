# autoscaling — Auto Scaling group + launch template (Phase 15)
#
# The classic AWS scaling unit: a launch template defines the instance
# template, and the Auto Scaling group (ASG) is the *reconciler* — it keeps
# the running instance count equal to the desired capacity, replacing
# terminated/unhealthy instances automatically.
#
# Floci probe findings (ADR-13): `aws_launch_configuration` resources FAIL on
# Floci (create returns success but describe returns empty → Terraform's
# post-create lookup errors with "empty result"). Launch templates DO persist,
# and an ASG backed by a launch template **genuinely launches EC2 instances
# and reconciles replacements** — terminate the ASG's instance and a new one
# is created (probe-verified: i-…a233 → terminated → i-…4c1c running). One
# quirk: the replacement stays `Pending` in the ASG's own view while the EC2
# instance is `running`. Launch templates are also the modern AWS best
# practice over launch configurations.

variable "asg_name" {
  type        = string
  description = "Name of the Auto Scaling group."
}

variable "environment" {
  type        = string
  default     = "dev"
  description = "Environment tag (dev/ci)."
}

variable "min_size" {
  type        = number
  default     = 1
  description = "Minimum instance count."
}

variable "max_size" {
  type        = number
  default     = 3
  description = "Maximum instance count."
}

variable "desired_capacity" {
  type        = number
  default     = 1
  description = "Desired instance count (the reconciler's target)."
}

# Launch template: the instance template. `ami-test` is the Floci EC2 image
# used by the rest of the project (Phase 8 CodeDeploy target).
resource "aws_launch_template" "app" {
  name          = "${var.asg_name}-lt"
  image_id      = "ami-test"
  instance_type = "t3.micro"
}

resource "aws_autoscaling_group" "app" {
  name              = var.asg_name
  min_size          = var.min_size
  max_size          = var.max_size
  desired_capacity  = var.desired_capacity
  health_check_type = "EC2"
  force_delete      = true
  # Explicit AZs are required on real AWS (no EC2-Classic); the ASG then
  # launches into the default VPC subnet of each AZ. Floci accepts and
  # honours them (probe-verified) — instances still launch + reconcile.
  availability_zones = ["us-east-1a", "us-east-1b"]

  launch_template {
    id      = aws_launch_template.app.id
    version = "$Latest"
  }

  tag {
    key                 = "Project"
    value               = "imageflow"
    propagate_at_launch = true
  }

  tag {
    key                 = "Environment"
    value               = var.environment
    propagate_at_launch = true
  }
}

output "asg_name" {
  value = aws_autoscaling_group.app.name
}

output "asg_arn" {
  value = aws_autoscaling_group.app.arn
}

output "desired_capacity" {
  value = aws_autoscaling_group.app.desired_capacity
}
