# =============================================================================
# Sunkworks Panic Button - Outputs
# =============================================================================

output "panic_button_function_arn" {
  description = "ARN of the panic button Lambda function"
  value       = aws_lambda_function.sunkworks_panic_button.arn
}

output "panic_button_function_name" {
  description = "Name of the panic button Lambda function"
  value       = aws_lambda_function.sunkworks_panic_button.function_name
}

output "recovery_function_arn" {
  description = "ARN of the panic recovery Lambda function"
  value       = aws_lambda_function.sunkworks_panic_recovery.arn
}

output "recovery_function_name" {
  description = "Name of the panic recovery Lambda function"
  value       = aws_lambda_function.sunkworks_panic_recovery.function_name
}

output "function_url" {
  description = "Function URL for quick access (if enabled)"
  value       = var.enable_function_url ? aws_lambda_function_url.sunkworks_panic_button[0].function_url : null
}

output "panic_button_role_arn" {
  description = "IAM role ARN for the panic button Lambda"
  value       = aws_iam_role.sunkworks_panic_button.arn
}
