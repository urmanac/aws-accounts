# Role ARNs
output "readonly_role_arn" {
  description = "ARN of the ReadOnly role"
  value       = aws_iam_role.readonly.arn
}

output "billing_role_arn" {
  description = "ARN of the Billing role"
  value       = aws_iam_role.billing.arn
}

output "security_role_arn" {
  description = "ARN of the Security role" 
  value       = aws_iam_role.security.arn
}

output "developer_role_arn" {
  description = "ARN of the Developer role"
  value       = aws_iam_role.developer.arn
}

output "admin_role_arn" {
  description = "ARN of the Admin role"
  value       = aws_iam_role.admin.arn
}

output "ci_role_arn" {
  description = "ARN of the CI role"
  value       = aws_iam_role.ci.arn
}

# Role Names (for AESR configuration)
output "readonly_role_name" {
  description = "Name of the ReadOnly role"
  value       = aws_iam_role.readonly.name
}

output "billing_role_name" {
  description = "Name of the Billing role"
  value       = aws_iam_role.billing.name
}

output "security_role_name" {
  description = "Name of the Security role"
  value       = aws_iam_role.security.name
}

output "developer_role_name" {
  description = "Name of the Developer role"
  value       = aws_iam_role.developer.name
}

output "admin_role_name" {
  description = "Name of the Admin role"
  value       = aws_iam_role.admin.name
}

output "ci_role_name" {
  description = "Name of the CI role"
  value       = aws_iam_role.ci.name
}

# Break-glass policy for emergency access
output "break_glass_policy_arn" {
  description = "ARN of the break-glass policy for emergency IAM user access"
  value       = aws_iam_policy.break_glass_assume_roles.arn
}

# All role ARNs for easy reference
output "all_role_arns" {
  description = "Map of all role ARNs"
  value = {
    readonly  = aws_iam_role.readonly.arn
    billing   = aws_iam_role.billing.arn
    security  = aws_iam_role.security.arn
    developer = aws_iam_role.developer.arn
    admin     = aws_iam_role.admin.arn
    ci        = aws_iam_role.ci.arn
  }
}

# Role information for AESR configuration
output "aesr_role_config" {
  description = "Role configuration data for AWS Extend Switch Roles"
  value = [
    {
      role_arn     = aws_iam_role.readonly.arn
      display_name = "ReadOnly"
      color        = "4CAF50"  # Green
    },
    {
      role_arn     = aws_iam_role.billing.arn
      display_name = "Billing"
      color        = "FF9800"  # Orange
    },
    {
      role_arn     = aws_iam_role.security.arn
      display_name = "Security"
      color        = "9C27B0"  # Purple
    },
    {
      role_arn     = aws_iam_role.developer.arn
      display_name = "Developer"
      color        = "2196F3"  # Blue
    },
    {
      role_arn     = aws_iam_role.admin.arn
      display_name = "Admin"
      color        = "F44336"  # Red
    },
    {
      role_arn     = aws_iam_role.ci.arn
      display_name = "CI"
      color        = "607D8B"  # Blue Grey
    }
  ]
}