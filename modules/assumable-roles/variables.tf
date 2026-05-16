variable "environment" {
  description = "Environment name (sb, prod)"
  type        = string
}

variable "role_prefix" {
  description = "Prefix for role names"
  type        = string
  default     = ""
}

variable "oidc_trust_policy" {
  description = "Trust policy document for OIDC provider integration"
  type        = string
}

variable "allowed_regions" {
  description = "List of AWS regions where resources can be created"
  type        = list(string)
  default     = ["us-east-1", "eu-west-1"]
}

# Session duration settings (in seconds)
variable "readonly_session_duration" {
  description = "Maximum session duration for ReadOnly role"
  type        = number
  default     = 14400  # 4 hours
}

variable "billing_session_duration" {
  description = "Maximum session duration for Billing role"
  type        = number
  default     = 7200   # 2 hours
}

variable "security_session_duration" {
  description = "Maximum session duration for Security role"
  type        = number
  default     = 3600   # 1 hour
}

variable "developer_session_duration" {
  description = "Maximum session duration for Developer role"
  type        = number
  default     = 28800  # 8 hours
}

variable "admin_session_duration" {
  description = "Maximum session duration for Admin role"
  type        = number
  default     = 3600   # 1 hour
}

variable "ci_session_duration" {
  description = "Maximum session duration for CI role"
  type        = number
  default     = 43200  # 12 hours
}