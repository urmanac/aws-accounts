# =============================================================================
# Sunkworks Episode Factory - Variables
# =============================================================================

variable "episode_name" {
  description = "Name of the episode (e.g., 'pihole', 'vind', 'turing')"
  type        = string
}

variable "episode_tag" {
  description = "Episode tag for resources (e.g., 'EP042-PIHOLE')"
  type        = string
}

variable "management_account_id" {
  description = "AWS account ID of the management/root account"
  type        = string
}

variable "vpc_cidr" {
  description = "CIDR block for the episode VPC"
  type        = string
  default     = "10.100.0.0/16"
}

variable "home_lab_cidrs" {
  description = "CIDR blocks for home lab SSH access"
  type        = list(string)
  default     = ["10.17.12.0/24", "10.17.13.0/24"]
}

variable "expiration_date" {
  description = "Date when the episode should be cleaned up (YYYY-MM-DD)"
  type        = string
}

variable "enable_budget_alerts" {
  description = "Enable AWS Budget alerts for this episode"
  type        = bool
  default     = true
}

variable "budget_limit" {
  description = "Maximum budget for this episode in USD"
  type        = string
  default     = "20"
}

variable "budget_alert_emails" {
  description = "Email addresses for budget alerts"
  type        = list(string)
  default     = []
}

variable "enable_auto_cleanup" {
  description = "Enable automatic cleanup after expiration"
  type        = bool
  default     = true
}
