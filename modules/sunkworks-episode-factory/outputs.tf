# =============================================================================
# Sunkworks Episode Factory - Outputs
# =============================================================================

output "vpc_id" {
  description = "VPC ID for the episode"
  value       = aws_vpc.sunkworks_episode.id
}

output "vpc_cidr" {
  description = "VPC CIDR block"
  value       = aws_vpc.sunkworks_episode.cidr_block
}

output "vpc_ipv6_cidr" {
  description = "VPC IPv6 CIDR block"
  value       = aws_vpc.sunkworks_episode.ipv6_cidr_block
}

output "public_subnet_ids" {
  description = "Public subnet IDs"
  value       = aws_subnet.public[*].id
}

output "private_subnet_ids" {
  description = "Private subnet IDs"
  value       = aws_subnet.private[*].id
}

output "default_security_group_id" {
  description = "Default security group ID for the episode"
  value       = aws_security_group.sunkworks_episode_default.id
}

output "episode_admin_role_arn" {
  description = "ARN of the episode admin role"
  value       = aws_iam_role.sunkworks_episode_admin.arn
}

output "episode_readonly_role_arn" {
  description = "ARN of the episode read-only role"
  value       = aws_iam_role.sunkworks_episode_readonly.arn
}

output "panic_button_role_arn" {
  description = "ARN of the panic button target role"
  value       = aws_iam_role.sunkworks_panic_button_target.arn
}

output "backup_vault_arn" {
  description = "ARN of the backup vault"
  value       = aws_backup_vault.sunkworks_episode.arn
}

output "log_group_name" {
  description = "CloudWatch log group name"
  value       = aws_cloudwatch_log_group.sunkworks_episode.name
}
