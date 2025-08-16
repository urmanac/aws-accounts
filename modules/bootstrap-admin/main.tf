# 0. Adopt existing IAM user
resource "aws_iam_user" "iamroot" {
  name = "${var.admin_username}"
  tags = {
    Environment = var.environment
    Role        = "admin"
  }
}

# 1. Create IAM user
resource "aws_iam_user" "admin" {
  name = "${var.admin_username}-${var.environment}"
  tags = {
    Environment = var.environment
    Role        = "admin"
  }
}

# 2. Group for admins
resource "aws_iam_group" "admins" {
  name = "admins-${var.environment}"
}

resource "aws_iam_group_policy_attachment" "admin_access" {
  group      = aws_iam_group.admins.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# 3. Membership
resource "aws_iam_user_group_membership" "admin_membership" {
  user   = aws_iam_user.admin.name
  groups = [aws_iam_group.admins.name]
}

resource "aws_iam_user_group_membership" "iamroot_membership" {
  user   = aws_iam_user.iamroot.name
  groups = [aws_iam_group.admins.name]
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
