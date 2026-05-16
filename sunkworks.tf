# =============================================================================
# Sunkworks Multi-Account Architecture
# =============================================================================
# Complete Terraform configuration for the Sunkworks streaming show's
# resilient multi-account AWS infrastructure.
# 
# Features:
# - Blast radius containment with SCPs
# - Episode isolation with separate accounts
# - Live stream safety rails
# - Panic button for cost protection
# - Cross-account backups
# - Discord/Slack notifications
# - Enhanced MFA with YubiKey support
# =============================================================================

terraform {
  required_version = ">= 1.0"
  
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Variables
# -----------------------------------------------------------------------------

variable "sunkworks_email_domain" {
  description = "Email domain for Sunkworks account creation"
  type        = string
}

variable "sunkworks_discord_webhook" {
  description = "Discord webhook URL for stream notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "sunkworks_slack_webhook" {
  description = "Slack webhook URL for stream notifications"
  type        = string
  default     = ""
  sensitive   = true
}

variable "sunkworks_budget_emails" {
  description = "Email addresses for budget alerts"
  type        = list(string)
  default     = []
}

variable "sunkworks_home_lab_cidrs" {
  description = "Home lab CIDR ranges for SSO device trust"
  type        = list(string)
  default     = ["10.17.12.0/24", "10.17.13.0/24"]
}

variable "sunkworks_approved_regions" {
  description = "AWS regions approved for Sunkworks resources"
  type        = list(string)
  default     = ["us-east-1", "eu-west-1"]
}

variable "sunkworks_enable_pihole" {
  description = "Enable Pi-hole episode account"
  type        = bool
  default     = false
}

variable "sunkworks_enable_vind" {
  description = "Enable Vind K8s episode account"
  type        = bool
  default     = false
}

variable "sunkworks_enable_turing" {
  description = "Enable Turing ARM64 episode account"
  type        = bool
  default     = false
}

variable "sunkworks_management_account_id" {
  description = "AWS account ID of the management account"
  type        = string
}

# -----------------------------------------------------------------------------
# AWS Organization with Episode Structure
# -----------------------------------------------------------------------------

module "sunkworks_organization" {
  source = "./modules/sunkworks-organization"
  
  email_domain = var.sunkworks_email_domain
  
  # Episode accounts
  enable_pihole_account  = var.sunkworks_enable_pihole
  enable_vind_account    = var.sunkworks_enable_vind
  enable_turing_account  = var.sunkworks_enable_turing
  
  # Episode configuration
  pihole_episode_tag     = "EP042-PIHOLE"
  pihole_expiration_date = "2026-03-31"
  
  vind_episode_tag       = "EP043-VIND"
  vind_expiration_date   = "2026-03-31"
  
  turing_episode_tag     = "EP044-TURING"
  turing_expiration_date = "2026-03-31"
  
  # Budget configuration
  enable_episode_budgets = true
  episode_budget_limit   = "20"
  budget_alert_emails    = var.sunkworks_budget_emails
  
  # Backup configuration
  backup_regions             = var.sunkworks_approved_regions
  enable_cross_region_backup = true
  backup_replica_region      = "eu-west-1"
}

# -----------------------------------------------------------------------------
# Service Control Policies - Blast Radius Containment
# -----------------------------------------------------------------------------

module "sunkworks_scps" {
  source = "./modules/sunkworks-scps"
  
  organization_root_id = module.sunkworks_organization.root_id
  episodes_ou_id       = module.sunkworks_organization.episodes_ou_id
  
  approved_regions = var.sunkworks_approved_regions
  
  # Cost controls - keep experiments affordable
  allowed_instance_types = [
    "t3.micro", "t3.small", "t3.medium",
    "t3a.micro", "t3a.small", "t3a.medium",
    "t4g.micro", "t4g.small", "t4g.medium"
  ]
  
  allowed_rds_classes = [
    "db.t3.micro", "db.t3.small",
    "db.t4g.micro", "db.t4g.small"
  ]
  
  max_ebs_size_gb = 100
}

# -----------------------------------------------------------------------------
# Stream Notifications - Discord/Slack Webhooks
# -----------------------------------------------------------------------------

module "sunkworks_notifications" {
  source = "./modules/sunkworks-notifications"
  
  discord_webhook_url = var.sunkworks_discord_webhook
  slack_webhook_url   = var.sunkworks_slack_webhook
  
  enable_terraform_notifications = true
  terraform_role_names = [
    "sb-CI",
    "prod-CI",
    "SunkworksOrganizationRole"
  ]
}

# -----------------------------------------------------------------------------
# Panic Button - Emergency Cost Protection
# -----------------------------------------------------------------------------

module "sunkworks_panic_button" {
  source = "./modules/sunkworks-panic-button"
  
  target_account_ids = module.sunkworks_organization.all_episode_account_ids
  
  # Exclude essential instances (bastion, etc.)
  excluded_instance_ids = []
  
  notification_sns_topic_arn = module.sunkworks_notifications.sns_topic_arn
  manifest_bucket_name       = module.sunkworks_backup.replica_bucket_name
  
  enable_function_url = false  # Set to true for quick access via URL
}

# -----------------------------------------------------------------------------
# Cross-Account Backup
# -----------------------------------------------------------------------------

module "sunkworks_backup" {
  source = "./modules/sunkworks-backup"
  
  backup_retention_days = 30
  
  enable_vault_lock          = false  # Enable for production
  vault_lock_min_retention   = 7
  vault_lock_max_retention   = 365
  vault_lock_changeable_days = 3
  
  enable_cross_region_copy = true
  backup_replica_region    = "eu-west-1"
  
  source_account_ids = module.sunkworks_organization.all_episode_account_ids
  
  tfstate_bucket_arns = [
    # Add your tfstate bucket ARNs here
  ]
  
  s3_version_retention_days = 90
  enable_glacier_transition = true
  enable_pre_apply_backup   = true
}

# -----------------------------------------------------------------------------
# Credential Rotation - Automatic on Exposure
# -----------------------------------------------------------------------------

module "sunkworks_credential_rotation" {
  source = "./modules/sunkworks-credential-rotation"
  
  sns_topic_arn            = module.sunkworks_notifications.sns_topic_arn
  enable_guardduty_trigger = true
}

# -----------------------------------------------------------------------------
# Outputs
# -----------------------------------------------------------------------------

output "sunkworks_organization_id" {
  description = "AWS Organization ID"
  value       = module.sunkworks_organization.organization_id
}

output "sunkworks_episodes_ou_id" {
  description = "Episodes OU ID"
  value       = module.sunkworks_organization.episodes_ou_id
}

output "sunkworks_episode_accounts" {
  description = "Episode account IDs"
  value = {
    pihole = module.sunkworks_organization.pihole_account_id
    vind   = module.sunkworks_organization.vind_account_id
    turing = module.sunkworks_organization.turing_account_id
  }
}

output "sunkworks_sns_topic_arn" {
  description = "SNS topic for stream notifications"
  value       = module.sunkworks_notifications.sns_topic_arn
}

output "sunkworks_panic_button_function" {
  description = "Panic button Lambda function name"
  value       = module.sunkworks_panic_button.panic_button_function_name
}

output "sunkworks_backup_vault" {
  description = "Central backup vault ARN"
  value       = module.sunkworks_backup.backup_vault_arn
}
