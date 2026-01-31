# =============================================================================
# Sunkworks Credential Rotation - Variables
# =============================================================================

variable "sns_topic_arn" {
  description = "SNS topic ARN for rotation notifications"
  type        = string
  default     = null
}

variable "enable_guardduty_trigger" {
  description = "Enable automatic rotation on GuardDuty findings"
  type        = bool
  default     = true
}
