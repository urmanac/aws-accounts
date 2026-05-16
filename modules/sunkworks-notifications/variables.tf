# =============================================================================
# Sunkworks Notifications - Variables
# =============================================================================

variable "discord_webhook_url" {
  description = "Discord webhook URL for notifications (sensitive)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "slack_webhook_url" {
  description = "Slack webhook URL for notifications (sensitive)"
  type        = string
  default     = ""
  sensitive   = true
}

variable "enable_terraform_notifications" {
  description = "Enable notifications for Terraform/CloudTrail events"
  type        = bool
  default     = true
}

variable "terraform_role_names" {
  description = "List of Terraform role names to monitor"
  type        = list(string)
  default     = ["sb-CI", "prod-CI", "SunkworksOrganizationRole"]
}
