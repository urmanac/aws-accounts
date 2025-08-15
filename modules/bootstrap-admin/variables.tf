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
}
