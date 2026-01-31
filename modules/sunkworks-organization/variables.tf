# =============================================================================
# Sunkworks Organization Module - Variables
# =============================================================================

variable "email_domain" {
  description = "Email domain for new account creation (e.g., example.com)"
  type        = string
}

# -----------------------------------------------------------------------------
# Episode Account Controls
# -----------------------------------------------------------------------------

variable "enable_pihole_account" {
  description = "Enable the sunkworks-pihole episode account"
  type        = bool
  default     = false
}

variable "enable_vind_account" {
  description = "Enable the sunkworks-vind Kubernetes episode account"
  type        = bool
  default     = false
}

variable "enable_turing_account" {
  description = "Enable the sunkworks-turing ARM64 episode account"
  type        = bool
  default     = false
}

# -----------------------------------------------------------------------------
# Episode Tags and Expiration
# -----------------------------------------------------------------------------

variable "pihole_episode_tag" {
  description = "Episode tag for Pi-hole account (e.g., 'EP042-PIHOLE')"
  type        = string
  default     = "EP000-PLACEHOLDER"
}

variable "vind_episode_tag" {
  description = "Episode tag for Vind K8s account"
  type        = string
  default     = "EP000-PLACEHOLDER"
}

variable "turing_episode_tag" {
  description = "Episode tag for Turing ARM64 account"
  type        = string
  default     = "EP000-PLACEHOLDER"
}

variable "pihole_expiration_date" {
  description = "When to auto-archive the Pi-hole account (YYYY-MM-DD)"
  type        = string
  default     = "2025-12-31"
}

variable "vind_expiration_date" {
  description = "When to auto-archive the Vind account"
  type        = string
  default     = "2025-12-31"
}

variable "turing_expiration_date" {
  description = "When to auto-archive the Turing account"
  type        = string
  default     = "2025-12-31"
}

variable "allowed_episode_tags" {
  description = "List of valid episode tag values for tag policy enforcement"
  type        = list(string)
  default = [
    "EP*",
    "SUNKWORKS-*",
    "TEST-*"
  ]
}

variable "episode_tags" {
  description = "Map of episode names to their tags"
  type        = map(string)
  default = {
    pihole = "EP042-PIHOLE"
    vind   = "EP043-VIND"
    turing = "EP044-TURING"
  }
}

# -----------------------------------------------------------------------------
# Budget Configuration
# -----------------------------------------------------------------------------

variable "enable_episode_budgets" {
  description = "Enable budget enforcement for episode accounts"
  type        = bool
  default     = true
}

variable "episode_budget_limit" {
  description = "Maximum budget per episode in USD"
  type        = string
  default     = "20"
}

variable "budget_alert_emails" {
  description = "Email addresses for budget alerts"
  type        = list(string)
  default     = []
}

# -----------------------------------------------------------------------------
# Backup Configuration
# -----------------------------------------------------------------------------

variable "backup_regions" {
  description = "Regions to enable backups in"
  type        = list(string)
  default     = ["us-east-1", "eu-west-1"]
}

variable "enable_cross_region_backup" {
  description = "Enable cross-region backup replication"
  type        = bool
  default     = true
}

variable "backup_replica_region" {
  description = "Region for backup replicas"
  type        = string
  default     = "eu-west-1"
}
