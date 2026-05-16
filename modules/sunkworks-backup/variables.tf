# =============================================================================
# Sunkworks Backup Module - Variables
# =============================================================================

variable "backup_retention_days" {
  description = "Days to retain backups"
  type        = number
  default     = 30
}

variable "enable_vault_lock" {
  description = "Enable vault lock for immutable backups"
  type        = bool
  default     = false
}

variable "vault_lock_min_retention" {
  description = "Minimum retention for vault lock (days)"
  type        = number
  default     = 7
}

variable "vault_lock_max_retention" {
  description = "Maximum retention for vault lock (days)"
  type        = number
  default     = 365
}

variable "vault_lock_changeable_days" {
  description = "Grace period before vault lock becomes immutable"
  type        = number
  default     = 3
}

variable "enable_cross_region_copy" {
  description = "Enable cross-region backup copies"
  type        = bool
  default     = true
}

variable "backup_replica_region" {
  description = "Region for backup replicas"
  type        = string
  default     = "eu-west-1"
}

variable "source_account_ids" {
  description = "AWS account IDs allowed to replicate to backup bucket"
  type        = list(string)
  default     = []
}

variable "tfstate_bucket_arns" {
  description = "ARNs of Terraform state buckets to backup"
  type        = list(string)
  default     = []
}

variable "s3_version_retention_days" {
  description = "Days to retain old S3 versions"
  type        = number
  default     = 90
}

variable "enable_glacier_transition" {
  description = "Enable transition to Glacier for old backups"
  type        = bool
  default     = true
}

variable "enable_pre_apply_backup" {
  description = "Enable Lambda for pre-terraform-apply backups"
  type        = bool
  default     = true
}
