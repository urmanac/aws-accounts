variable "environment" {
  description = "Environment name (sb, prod)"
  type        = string
}

# GitHub OIDC Configuration
variable "enable_github_oidc" {
  description = "Enable GitHub OIDC provider"
  type        = bool
  default     = true
}

variable "github_organizations" {
  description = "List of GitHub organizations allowed to assume roles"
  type        = list(string)
  default     = ["urmanac", "kingdon-ci"]
}

# GitLab OIDC Configuration  
variable "enable_gitlab_oidc" {
  description = "Enable GitLab OIDC provider"
  type        = bool
  default     = false
}

variable "gitlab_projects" {
  description = "List of GitLab projects allowed to assume roles"
  type        = list(string)
  default     = []
}

# Custom OIDC Configuration (Keycloak, Auth0, etc.)
variable "enable_custom_oidc" {
  description = "Enable custom OIDC provider"
  type        = bool
  default     = false
}

variable "custom_oidc_url" {
  description = "URL of the custom OIDC provider"
  type        = string
  default     = ""
}

variable "custom_oidc_client_ids" {
  description = "List of client IDs for custom OIDC provider"
  type        = list(string)
  default     = ["sts.amazonaws.com"]
}

variable "custom_oidc_thumbprints" {
  description = "List of server certificate thumbprints for custom OIDC provider"
  type        = list(string)
  default     = []
}

variable "custom_oidc_conditions" {
  description = "List of trust policy conditions for custom OIDC provider"
  type = list(object({
    test     = string
    variable = string
    values   = list(string)
  }))
  default = []
}