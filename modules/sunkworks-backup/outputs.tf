# =============================================================================
# Sunkworks Backup Module - Outputs
# =============================================================================

output "backup_vault_arn" {
  description = "ARN of the central backup vault"
  value       = aws_backup_vault.sunkworks_central.arn
}

output "backup_vault_name" {
  description = "Name of the central backup vault"
  value       = aws_backup_vault.sunkworks_central.name
}

output "backup_plan_id" {
  description = "ID of the daily backup plan"
  value       = aws_backup_plan.sunkworks_daily.id
}

output "backup_role_arn" {
  description = "ARN of the backup IAM role"
  value       = aws_iam_role.sunkworks_backup.arn
}

output "replica_bucket_arn" {
  description = "ARN of the S3 replica bucket"
  value       = aws_s3_bucket.sunkworks_backup_replica.arn
}

output "replica_bucket_name" {
  description = "Name of the S3 replica bucket"
  value       = aws_s3_bucket.sunkworks_backup_replica.id
}

output "pre_apply_lambda_arn" {
  description = "ARN of the pre-apply backup Lambda (if enabled)"
  value       = var.enable_pre_apply_backup ? aws_lambda_function.sunkworks_pre_apply_backup[0].arn : null
}
