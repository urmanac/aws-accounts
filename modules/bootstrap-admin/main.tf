# Get current AWS account ID
data "aws_caller_identity" "current" {}

# 0. Adopt existing IAM user (now for break-glass access only)
resource "aws_iam_user" "iamroot" {
  name = "${var.admin_username}"
  tags = {
    Environment = var.environment
    Role        = "break-glass-admin"
    Purpose     = "Emergency access when OIDC is unavailable"
  }
}

# 1. Create IAM user (now for break-glass access only)
resource "aws_iam_user" "admin" {
  name = "${var.admin_username}-${var.environment}"
  tags = {
    Environment = var.environment
    Role        = "break-glass-admin"
    Purpose     = "Emergency access when OIDC is unavailable"
  }
}

# 2. Group for break-glass admins (minimal permissions)
resource "aws_iam_group" "break_glass_admins" {
  name = "break-glass-admins-${var.environment}"
}

# Break-glass users can only change passwords, manage MFA, and assume roles
resource "aws_iam_policy" "break_glass_base_permissions" {
  name        = "BreakGlassBasePermissions-${var.environment}"
  description = "Minimal permissions for break-glass IAM users in ${var.environment}"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowSelfManagement"
        Effect = "Allow"
        Action = [
          "iam:ChangePassword",
          "iam:GetAccountPasswordPolicy",
          "iam:GetAccountSummary",
          "iam:GetUser",
          "iam:ListVirtualMFADevices",
          "iam:ListMFADevices",
          "iam:ResyncMFADevice",
          "iam:CreateVirtualMFADevice",
          "iam:EnableMFADevice",
          "iam:DeactivateMFADevice",
          "iam:DeleteVirtualMFADevice"
        ]
        Resource = [
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:user/$${aws:username}",
          "arn:aws:iam::${data.aws_caller_identity.current.account_id}:mfa/$${aws:username}"
        ]
      },
      {
        Sid    = "AllowSTSOperations"
        Effect = "Allow"
        Action = [
          "sts:GetSessionToken",
          "sts:GetCallerIdentity"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_group_policy_attachment" "break_glass_base" {
  group      = aws_iam_group.break_glass_admins.name
  policy_arn = aws_iam_policy.break_glass_base_permissions.arn
}

# Attach break-glass role assumption policy if provided
resource "aws_iam_group_policy_attachment" "break_glass_assume_roles" {
  count      = var.break_glass_assume_roles_policy_arn != null ? 1 : 0
  group      = aws_iam_group.break_glass_admins.name
  policy_arn = var.break_glass_assume_roles_policy_arn
}

# 3. Membership (break-glass group instead of admin group)
resource "aws_iam_user_group_membership" "admin_membership" {
  user   = aws_iam_user.admin.name
  groups = [aws_iam_group.break_glass_admins.name]
}

resource "aws_iam_user_group_membership" "iamroot_membership" {
  user   = aws_iam_user.iamroot.name
  groups = [aws_iam_group.break_glass_admins.name]
}

# 4. MFA enforcement policy
data "aws_iam_policy_document" "require_mfa" {
  statement {
    sid    = "BlockMostAccessUnlessMFA"
    effect = "Deny"

    not_actions = [
      "iam:ChangePassword",
      "iam:GetAccountPasswordPolicy",
      "iam:GetAccountSummary",
      "iam:ListVirtualMFADevices",
      "iam:ListUsers",
      "iam:ListMFADevices",
      "iam:ResyncMFADevice",
      "sts:GetSessionToken"
    ]

    resources = ["*"]

    condition {
      test     = "BoolIfExists"
      variable = "aws:MultiFactorAuthPresent"
      values   = ["false"]
    }
  }
}

resource "aws_iam_policy" "require_mfa" {
  name        = "RequireMFA-${var.environment}"
  description = "Enforce MFA for most actions in ${var.environment} account"
  policy      = data.aws_iam_policy_document.require_mfa.json
}

resource "aws_iam_user_policy_attachment" "attach_mfa" {
  user       = aws_iam_user.admin.name
  policy_arn = aws_iam_policy.require_mfa.arn
}

resource "aws_iam_user_policy_attachment" "attach_mfa_iamroot" {
  user       = aws_iam_user.iamroot.name
  policy_arn = aws_iam_policy.require_mfa.arn
}

resource "aws_iam_policy" "cost_explorer_access" {
  name        = "CostExplorerAccess"
  description = "Grants permissions to view AWS Cost Explorer data"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect   = "Allow"
        Action   = [
          "ce:GetCostAndUsage",
          "ce:GetCostForecast",
          "ce:GetReservationUtilization",
          "ce:GetReservationPurchaseRecommendation",
          "ce:DescribeReport",
          "ce:GetDimensionValues"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_user_policy_attachment" "terraform_iamroot_cost_explorer" {
  user       = aws_iam_user.iamroot.name
  policy_arn = aws_iam_policy.cost_explorer_access.arn
}
