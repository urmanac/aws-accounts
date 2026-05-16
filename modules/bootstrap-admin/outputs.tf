output "admin_username" {
  description = "Name of the break-glass admin user"
  value       = aws_iam_user.admin.name
}

output "admin_policy_arn" {
  description = "ARN of the MFA requirement policy"
  value       = aws_iam_policy.require_mfa.arn
}

output "break_glass_group_name" {
  description = "Name of the break-glass administrators group"
  value       = aws_iam_group.break_glass_admins.name
}

output "break_glass_base_policy_arn" {
  description = "ARN of the break-glass base permissions policy"
  value       = aws_iam_policy.break_glass_base_permissions.arn
}
