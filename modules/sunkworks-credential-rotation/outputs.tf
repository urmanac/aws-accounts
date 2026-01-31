# =============================================================================
# Sunkworks Credential Rotation - Outputs
# =============================================================================

output "lambda_function_arn" {
  description = "ARN of the credential rotation Lambda"
  value       = aws_lambda_function.sunkworks_credential_rotation.arn
}

output "lambda_function_name" {
  description = "Name of the credential rotation Lambda"
  value       = aws_lambda_function.sunkworks_credential_rotation.function_name
}

output "rotation_role_arn" {
  description = "IAM role ARN for the rotation Lambda"
  value       = aws_iam_role.sunkworks_credential_rotation.arn
}
