variable "environment" {
  type        = string
  description = "Environment name (sb, prod)"
}

variable "account_id" {
  type        = string
  description = "AWS Account ID for this environment"
}

variable "admin_username" {
  type        = string
  default     = "terraform-admin"
  description = "Username for break-glass admin accounts (legacy naming)"
}

variable "break_glass_assume_roles_policy_arn" {
  type        = string
  default     = null
  description = "ARN of policy allowing break-glass users to assume OIDC roles"
}
