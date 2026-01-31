# =============================================================================
# Sunkworks AWS Organizations - Multi-Account Blast Radius Containment
# =============================================================================
# This module creates an AWS Organization structure optimized for the Sunkworks
# streaming show, with automatic episode isolation and budget enforcement.
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
# AWS Organization - Root
# -----------------------------------------------------------------------------
resource "aws_organizations_organization" "sunkworks" {
  aws_service_access_principals = [
    "cloudtrail.amazonaws.com",
    "config.amazonaws.com",
    "sso.amazonaws.com",
    "tagpolicies.tag.amazonaws.com",
    "backup.amazonaws.com",
    "cost-management.amazonaws.com"
  ]

  feature_set = "ALL"

  enabled_policy_types = [
    "SERVICE_CONTROL_POLICY",
    "TAG_POLICY",
    "BACKUP_POLICY"
  ]
}

# -----------------------------------------------------------------------------
# Organizational Units
# -----------------------------------------------------------------------------

# Core OU - Management and shared services (no experiments here)
resource "aws_organizations_organizational_unit" "core" {
  name      = "sunkworks-core"
  parent_id = aws_organizations_organization.sunkworks.roots[0].id
}

# Episodes OU - Contains all Sunkworks episode experiment accounts
resource "aws_organizations_organizational_unit" "episodes" {
  name      = "sunkworks-episodes"
  parent_id = aws_organizations_organization.sunkworks.roots[0].id
}

# Archive OU - Suspended accounts from completed episodes (read-only)
resource "aws_organizations_organizational_unit" "archive" {
  name      = "sunkworks-archive"
  parent_id = aws_organizations_organization.sunkworks.roots[0].id
}

# Sandbox OU - Free-form experimentation (highest risk tolerance)
resource "aws_organizations_organizational_unit" "sandbox" {
  name      = "sunkworks-sandbox"
  parent_id = aws_organizations_organization.sunkworks.roots[0].id
}

# -----------------------------------------------------------------------------
# Episode Accounts - Per-experiment isolation
# -----------------------------------------------------------------------------

resource "aws_organizations_account" "sunkworks_pihole" {
  count = var.enable_pihole_account ? 1 : 0

  name              = "sunkworks-pihole"
  email             = "sunkworks-pihole@${var.email_domain}"
  role_name         = "SunkworksOrganizationRole"
  parent_id         = aws_organizations_organizational_unit.episodes.id
  close_on_deletion = true

  tags = {
    Name           = "sunkworks-pihole"
    Episode        = var.pihole_episode_tag
    Purpose        = "DNS experiments and Pi-hole infrastructure"
    BudgetLimit    = "$20"
    AutoCleanup    = "true"
    ExpirationDate = var.pihole_expiration_date
  }

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "sunkworks_vind" {
  count = var.enable_vind_account ? 1 : 0

  name              = "sunkworks-vind"
  email             = "sunkworks-vind@${var.email_domain}"
  role_name         = "SunkworksOrganizationRole"
  parent_id         = aws_organizations_organizational_unit.episodes.id
  close_on_deletion = true

  tags = {
    Name           = "sunkworks-vind"
    Episode        = var.vind_episode_tag
    Purpose        = "Kubernetes testing with disposable t4g instances"
    BudgetLimit    = "$20"
    AutoCleanup    = "true"
    ExpirationDate = var.vind_expiration_date
  }

  lifecycle {
    ignore_changes = [role_name]
  }
}

resource "aws_organizations_account" "sunkworks_turing" {
  count = var.enable_turing_account ? 1 : 0

  name              = "sunkworks-turing"
  email             = "sunkworks-turing@${var.email_domain}"
  role_name         = "SunkworksOrganizationRole"
  parent_id         = aws_organizations_organizational_unit.episodes.id
  close_on_deletion = true

  tags = {
    Name           = "sunkworks-turing"
    Episode        = var.turing_episode_tag
    Purpose        = "ARM64 hardware emulation experiments"
    BudgetLimit    = "$20"
    AutoCleanup    = "true"
    ExpirationDate = var.turing_expiration_date
  }

  lifecycle {
    ignore_changes = [role_name]
  }
}

# -----------------------------------------------------------------------------
# Tag Policies - Enforce episode tagging
# -----------------------------------------------------------------------------

resource "aws_organizations_policy" "sunkworks_tagging" {
  name        = "sunkworks-episode-tagging"
  description = "Enforce consistent tagging for Sunkworks episode resources"
  type        = "TAG_POLICY"

  content = jsonencode({
    tags = {
      Episode = {
        tag_key = {
          "@@assign" = "Episode"
        }
        tag_value = {
          "@@assign" = var.allowed_episode_tags
        }
        enforced_for = {
          "@@assign" = [
            "ec2:instance",
            "ec2:volume",
            "s3:bucket",
            "lambda:function",
            "rds:db"
          ]
        }
      }
      CostCenter = {
        tag_key = {
          "@@assign" = "CostCenter"
        }
        tag_value = {
          "@@assign" = ["sunkworks-streaming"]
        }
      }
    }
  })
}

resource "aws_organizations_policy_attachment" "tagging_episodes" {
  policy_id = aws_organizations_policy.sunkworks_tagging.id
  target_id = aws_organizations_organizational_unit.episodes.id
}

# -----------------------------------------------------------------------------
# Backup Policies - Automated cross-account backup
# -----------------------------------------------------------------------------

resource "aws_organizations_policy" "sunkworks_backup" {
  name        = "sunkworks-backup-policy"
  description = "Automated backup policy for Sunkworks episode resources"
  type        = "BACKUP_POLICY"

  content = jsonencode({
    plans = {
      "sunkworks-episode-backup" = {
        regions = {
          "@@assign" = var.backup_regions
        }
        rules = {
          "daily-backup" = {
            lifecycle = {
              delete_after_days = {
                "@@assign" = 7
              }
            }
            target_backup_vault_name = {
              "@@assign" = "sunkworks-vault"
            }
            schedule_expression = {
              "@@assign" = "cron(0 5 ? * * *)"
            }
            copy_actions = var.enable_cross_region_backup ? {
              "arn:aws:backup:${var.backup_replica_region}:$account:backup-vault:sunkworks-vault-replica" = {
                lifecycle = {
                  delete_after_days = {
                    "@@assign" = 30
                  }
                }
              }
            } : {}
          }
        }
        selections = {
          tags = {
            "episode-resources" = {
              iam_role_arn = {
                "@@assign" = "arn:aws:iam::$account:role/SunkworksBackupRole"
              }
              tag_key = {
                "@@assign" = "Episode"
              }
              tag_value = {
                "@@assign" = var.allowed_episode_tags
              }
            }
          }
        }
      }
    }
  })
}

resource "aws_organizations_policy_attachment" "backup_episodes" {
  policy_id = aws_organizations_policy.sunkworks_backup.id
  target_id = aws_organizations_organizational_unit.episodes.id
}

# -----------------------------------------------------------------------------
# Budget Enforcement - $20/episode max
# -----------------------------------------------------------------------------

resource "aws_budgets_budget" "sunkworks_episode_budget" {
  for_each = toset(var.enable_episode_budgets ? ["pihole", "vind", "turing"] : [])

  name              = "sunkworks-${each.key}-budget"
  budget_type       = "COST"
  limit_amount      = var.episode_budget_limit
  limit_unit        = "USD"
  time_period_start = "2024-01-01_00:00"
  time_unit         = "MONTHLY"

  cost_filter {
    name   = "TagKeyValue"
    values = ["Episode$${var.episode_tags[each.key]}"]
  }

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
