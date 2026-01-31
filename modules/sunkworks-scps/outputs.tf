# =============================================================================
# Sunkworks SCPs - Outputs
# =============================================================================

output "deny_root_policy_id" {
  description = "ID of the deny root account SCP"
  value       = aws_organizations_policy.sunkworks_deny_root.id
}

output "protect_instances_policy_id" {
  description = "ID of the instance protection SCP"
  value       = aws_organizations_policy.sunkworks_protect_instances.id
}

output "protect_network_policy_id" {
  description = "ID of the network protection SCP"
  value       = aws_organizations_policy.sunkworks_protect_network.id
}

output "protect_s3_policy_id" {
  description = "ID of the S3 protection SCP"
  value       = aws_organizations_policy.sunkworks_protect_s3.id
}

output "region_restriction_policy_id" {
  description = "ID of the region restriction SCP"
  value       = aws_organizations_policy.sunkworks_region_restriction.id
}

output "cost_controls_policy_id" {
  description = "ID of the cost controls SCP"
  value       = aws_organizations_policy.sunkworks_cost_controls.id
}

output "iam_guardrails_policy_id" {
  description = "ID of the IAM guardrails SCP"
  value       = aws_organizations_policy.sunkworks_iam_guardrails.id
}

output "all_scp_ids" {
  description = "List of all SCP IDs"
  value = [
    aws_organizations_policy.sunkworks_deny_root.id,
    aws_organizations_policy.sunkworks_protect_instances.id,
    aws_organizations_policy.sunkworks_protect_network.id,
    aws_organizations_policy.sunkworks_protect_s3.id,
    aws_organizations_policy.sunkworks_region_restriction.id,
    aws_organizations_policy.sunkworks_cost_controls.id,
    aws_organizations_policy.sunkworks_iam_guardrails.id
  ]
}
