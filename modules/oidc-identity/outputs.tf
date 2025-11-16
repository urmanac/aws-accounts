# OIDC Provider ARNs
output "github_oidc_provider_arn" {
  description = "ARN of the GitHub OIDC provider"
  value       = var.enable_github_oidc ? aws_iam_openid_connect_provider.github[0].arn : null
}

output "gitlab_oidc_provider_arn" {
  description = "ARN of the GitLab OIDC provider"
  value       = var.enable_gitlab_oidc ? aws_iam_openid_connect_provider.gitlab[0].arn : null
}

output "custom_oidc_provider_arn" {
  description = "ARN of the custom OIDC provider"
  value       = var.enable_custom_oidc ? aws_iam_openid_connect_provider.custom[0].arn : null
}

# Trust Policy Documents
output "github_oidc_trust_policy" {
  description = "Trust policy document for GitHub OIDC"
  value       = var.enable_github_oidc ? data.aws_iam_policy_document.github_oidc_trust[0].json : null
}

output "gitlab_oidc_trust_policy" {
  description = "Trust policy document for GitLab OIDC"
  value       = var.enable_gitlab_oidc ? data.aws_iam_policy_document.gitlab_oidc_trust[0].json : null
}

output "custom_oidc_trust_policy" {
  description = "Trust policy document for custom OIDC"
  value       = var.enable_custom_oidc ? data.aws_iam_policy_document.custom_oidc_trust[0].json : null
}

output "multi_provider_trust_policy" {
  description = "Combined trust policy document for all enabled OIDC providers"
  value       = data.aws_iam_policy_document.multi_provider_trust.json
}

# Provider Information
output "enabled_providers" {
  description = "List of enabled OIDC providers"
  value = compact([
    var.enable_github_oidc ? "github" : "",
    var.enable_gitlab_oidc ? "gitlab" : "",
    var.enable_custom_oidc ? "custom" : ""
  ])
}

output "github_organizations" {
  description = "GitHub organizations configured for OIDC access"
  value       = var.github_organizations
}

output "gitlab_projects" {
  description = "GitLab projects configured for OIDC access"
  value       = var.gitlab_projects
}