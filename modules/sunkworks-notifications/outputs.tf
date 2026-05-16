# =============================================================================
# Sunkworks Notifications - Outputs
# =============================================================================

output "sns_topic_arn" {
  description = "ARN of the SNS topic for Sunkworks alerts"
  value       = aws_sns_topic.sunkworks_alerts.arn
}

output "sns_topic_name" {
  description = "Name of the SNS topic"
  value       = aws_sns_topic.sunkworks_alerts.name
}

output "webhook_lambda_arn" {
  description = "ARN of the webhook Lambda function"
  value       = aws_lambda_function.sunkworks_webhook.arn
}

output "webhook_lambda_name" {
  description = "Name of the webhook Lambda function"
  value       = aws_lambda_function.sunkworks_webhook.function_name
}
