# =============================================================================
# Sunkworks Organization Module - Outputs
# =============================================================================

output "organization_id" {
  description = "AWS Organization ID"
  value       = aws_organizations_organization.sunkworks.id
}

output "organization_arn" {
  description = "AWS Organization ARN"
  value       = aws_organizations_organization.sunkworks.arn
}

output "root_id" {
  description = "Root ID of the organization"
  value       = aws_organizations_organization.sunkworks.roots[0].id
}

output "core_ou_id" {
  description = "Core organizational unit ID"
  value       = aws_organizations_organizational_unit.core.id
}

output "episodes_ou_id" {
  description = "Episodes organizational unit ID"
  value       = aws_organizations_organizational_unit.episodes.id
}

output "archive_ou_id" {
  description = "Archive organizational unit ID"
  value       = aws_organizations_organizational_unit.archive.id
}

output "sandbox_ou_id" {
  description = "Sandbox organizational unit ID"
  value       = aws_organizations_organizational_unit.sandbox.id
}

output "pihole_account_id" {
  description = "Sunkworks Pi-hole account ID"
  value       = var.enable_pihole_account ? aws_organizations_account.sunkworks_pihole[0].id : null
}

output "vind_account_id" {
  description = "Sunkworks Vind K8s account ID"
  value       = var.enable_vind_account ? aws_organizations_account.sunkworks_vind[0].id : null
}

output "turing_account_id" {
  description = "Sunkworks Turing ARM64 account ID"
  value       = var.enable_turing_account ? aws_organizations_account.sunkworks_turing[0].id : null
}

output "all_episode_account_ids" {
  description = "List of all episode account IDs"
  value = compact([
    var.enable_pihole_account ? aws_organizations_account.sunkworks_pihole[0].id : "",
    var.enable_vind_account ? aws_organizations_account.sunkworks_vind[0].id : "",
    var.enable_turing_account ? aws_organizations_account.sunkworks_turing[0].id : ""
  ])
}
