output "admin_username" {
  value = aws_iam_user.admin.name
}

output "admin_policy_arn" {
  value = aws_iam_policy.require_mfa.arn
}
