# =============================================================================
# Sunkworks Panic Button - Variables
# =============================================================================

variable "target_account_ids" {
  description = "List of AWS account IDs where panic button can operate"
  type        = list(string)
}

variable "excluded_instance_ids" {
  description = "Instance IDs to never stop (bastion hosts, etc.)"
  type        = list(string)
  default     = []
}

variable "notification_sns_topic_arn" {
  description = "SNS topic ARN for panic button notifications"
  type        = string
  default     = null
}

variable "manifest_bucket_name" {
  description = "S3 bucket name for storing recovery manifests"
  type        = string
  default     = null
}

variable "enable_function_url" {
  description = "Enable Lambda Function URL for quick access"
  type        = bool
  default     = false
}
