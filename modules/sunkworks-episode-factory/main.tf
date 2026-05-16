# =============================================================================
# Sunkworks Episode Factory - Ephemeral Account Management
# =============================================================================
# Creates and manages ephemeral AWS accounts for Sunkworks episodes with
# automatic cleanup, budget enforcement, and isolated VPCs.
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Episode Account Bootstrap
# -----------------------------------------------------------------------------

# This module is called once per episode account to bootstrap it with
# the necessary resources for Sunkworks operations.

# Get account info
data "aws_caller_identity" "current" {}
data "aws_region" "current" {}

# -----------------------------------------------------------------------------
# Episode VPC - Isolated networking per episode
# -----------------------------------------------------------------------------

resource "aws_vpc" "sunkworks_episode" {
  cidr_block                       = var.vpc_cidr
  assign_generated_ipv6_cidr_block = true
  enable_dns_hostnames             = true
  enable_dns_support               = true

  tags = {
    Name             = "sunkworks-${var.episode_name}-vpc"
    Episode          = var.episode_tag
    NetworkProtected = "true"
    SunkworksManaged = "true"
    ExpirationDate   = var.expiration_date
  }
}

# -----------------------------------------------------------------------------
# Subnets - Public and Private per AZ
# -----------------------------------------------------------------------------

data "aws_availability_zones" "available" {
  state = "available"
}

resource "aws_subnet" "public" {
  count = min(2, length(data.aws_availability_zones.available.names))

  vpc_id                          = aws_vpc.sunkworks_episode.id
  cidr_block                      = cidrsubnet(var.vpc_cidr, 4, count.index)
  ipv6_cidr_block                 = cidrsubnet(aws_vpc.sunkworks_episode.ipv6_cidr_block, 8, count.index)
  availability_zone               = data.aws_availability_zones.available.names[count.index]
  map_public_ip_on_launch         = false  # IPv6-only design

  tags = {
    Name             = "sunkworks-${var.episode_name}-public-${count.index}"
    Episode          = var.episode_tag
    NetworkProtected = "true"
    SunkworksManaged = "true"
  }
}

resource "aws_subnet" "private" {
  count = min(2, length(data.aws_availability_zones.available.names))

  vpc_id            = aws_vpc.sunkworks_episode.id
  cidr_block        = cidrsubnet(var.vpc_cidr, 4, count.index + 10)
  ipv6_cidr_block   = cidrsubnet(aws_vpc.sunkworks_episode.ipv6_cidr_block, 8, count.index + 10)
  availability_zone = data.aws_availability_zones.available.names[count.index]

  tags = {
    Name             = "sunkworks-${var.episode_name}-private-${count.index}"
    Episode          = var.episode_tag
    NetworkProtected = "true"
    SunkworksManaged = "true"
  }
}

# -----------------------------------------------------------------------------
# Internet Gateway
# -----------------------------------------------------------------------------

resource "aws_internet_gateway" "sunkworks_episode" {
  vpc_id = aws_vpc.sunkworks_episode.id

  tags = {
    Name             = "sunkworks-${var.episode_name}-igw"
    Episode          = var.episode_tag
    NetworkProtected = "true"
    SunkworksManaged = "true"
  }
}

# -----------------------------------------------------------------------------
# Route Tables
# -----------------------------------------------------------------------------

resource "aws_route_table" "public" {
  vpc_id = aws_vpc.sunkworks_episode.id

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.sunkworks_episode.id
  }

  route {
    ipv6_cidr_block = "::/0"
    gateway_id      = aws_internet_gateway.sunkworks_episode.id
  }

  tags = {
    Name             = "sunkworks-${var.episode_name}-public-rt"
    Episode          = var.episode_tag
    NetworkProtected = "true"
    SunkworksManaged = "true"
  }
}

resource "aws_route_table_association" "public" {
  count = length(aws_subnet.public)

  subnet_id      = aws_subnet.public[count.index].id
  route_table_id = aws_route_table.public.id
}

# -----------------------------------------------------------------------------
# Security Group - Default Episode SG
# -----------------------------------------------------------------------------

resource "aws_security_group" "sunkworks_episode_default" {
  name        = "sunkworks-${var.episode_name}-default"
  description = "Default security group for Sunkworks episode ${var.episode_name}"
  vpc_id      = aws_vpc.sunkworks_episode.id

  # Allow all outbound
  egress {
    from_port        = 0
    to_port          = 0
    protocol         = "-1"
    cidr_blocks      = ["0.0.0.0/0"]
    ipv6_cidr_blocks = ["::/0"]
  }

  # Allow SSH from home lab ranges
  dynamic "ingress" {
    for_each = var.home_lab_cidrs
    content {
      from_port   = 22
      to_port     = 22
      protocol    = "tcp"
      cidr_blocks = [ingress.value]
      description = "SSH from home lab"
    }
  }

  # Allow all internal VPC traffic
  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    self        = true
    description = "All VPC internal traffic"
  }

  tags = {
    Name             = "sunkworks-${var.episode_name}-default-sg"
    Episode          = var.episode_tag
    SunkworksManaged = "true"
  }
}

# -----------------------------------------------------------------------------
# Episode IAM Roles
# -----------------------------------------------------------------------------

# Admin role for the episode (assumable from management account)
resource "aws_iam_role" "sunkworks_episode_admin" {
  name = "SunkworksEpisodeAdmin"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.management_account_id}:root"
        }
        Action = "sts:AssumeRole"
        Condition = {
          Bool = {
            "aws:MultiFactorAuthPresent" = "true"
          }
        }
      }
    ]
  })

  max_session_duration = 14400

  tags = {
    Name             = "SunkworksEpisodeAdmin"
    Episode          = var.episode_tag
    SunkworksManaged = "true"
  }
}

resource "aws_iam_role_policy_attachment" "episode_admin" {
  role       = aws_iam_role.sunkworks_episode_admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# ReadOnly role for monitoring
resource "aws_iam_role" "sunkworks_episode_readonly" {
  name = "SunkworksEpisodeReadOnly"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.management_account_id}:root"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  max_session_duration = 43200

  tags = {
    Name             = "SunkworksEpisodeReadOnly"
    Episode          = var.episode_tag
    SunkworksManaged = "true"
  }
}

resource "aws_iam_role_policy_attachment" "episode_readonly" {
  role       = aws_iam_role.sunkworks_episode_readonly.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Panic button role (uses the same policy defined in panic-button module)
resource "aws_iam_role" "sunkworks_panic_button_target" {
  name = "SunkworksPanicButtonRole"

  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::${var.management_account_id}:role/sunkworks-panic-button-role"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })

  tags = {
    Name             = "SunkworksPanicButtonRole"
    Episode          = var.episode_tag
    SunkworksManaged = "true"
  }
}

resource "aws_iam_policy" "sunkworks_panic_button_target" {
  name        = "SunkworksPanicButtonTargetPolicy"
  description = "Permissions for panic button Lambda to manage instances"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:SuspendProcesses",
          "autoscaling:ResumeProcesses",
          "autoscaling:UpdateAutoScalingGroup"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "panic_button_target" {
  role       = aws_iam_role.sunkworks_panic_button_target.name
  policy_arn = aws_iam_policy.sunkworks_panic_button_target.arn
}

# -----------------------------------------------------------------------------
# AWS Backup Vault for episode resources
# -----------------------------------------------------------------------------

resource "aws_backup_vault" "sunkworks_episode" {
  name = "sunkworks-${var.episode_name}-vault"

  tags = {
    Name             = "sunkworks-${var.episode_name}-vault"
    Episode          = var.episode_tag
    SunkworksManaged = "true"
  }
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group for episode
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "sunkworks_episode" {
  name              = "/sunkworks/${var.episode_name}"
  retention_in_days = 7  # Short retention for ephemeral episodes

  tags = {
    Name             = "sunkworks-${var.episode_name}-logs"
    Episode          = var.episode_tag
    SunkworksManaged = "true"
  }
}

# -----------------------------------------------------------------------------
# Budget Alert for episode
# -----------------------------------------------------------------------------

resource "aws_budgets_budget" "sunkworks_episode" {
  count = var.enable_budget_alerts ? 1 : 0

  name              = "sunkworks-${var.episode_name}-budget"
  budget_type       = "COST"
  limit_amount      = var.budget_limit
  limit_unit        = "USD"
  time_period_start = "2024-01-01_00:00"
  time_unit         = "MONTHLY"

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 50
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 80
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_emails
  }

  notification {
    comparison_operator        = "GREATER_THAN"
    threshold                  = 100
    threshold_type             = "PERCENTAGE"
    notification_type          = "ACTUAL"
    subscriber_email_addresses = var.budget_alert_emails
  }
}

# -----------------------------------------------------------------------------
# Cleanup Automation - EventBridge rule to trigger cleanup
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "sunkworks_episode_cleanup" {
  count = var.enable_auto_cleanup ? 1 : 0

  name                = "sunkworks-${var.episode_name}-cleanup"
  description         = "Trigger cleanup for episode ${var.episode_name}"
  schedule_expression = "cron(0 0 ${formatdate("D", var.expiration_date)} ${formatdate("M", var.expiration_date)} ? ${formatdate("YYYY", var.expiration_date)})"

  tags = {
    Name             = "sunkworks-${var.episode_name}-cleanup-rule"
    Episode          = var.episode_tag
    SunkworksManaged = "true"
  }
}
