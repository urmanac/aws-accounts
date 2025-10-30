terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# ReadOnly Role - Investigation, monitoring, compliance
resource "aws_iam_role" "readonly" {
  name               = "${var.role_prefix}ReadOnly"
  assume_role_policy = var.oidc_trust_policy
  max_session_duration = var.readonly_session_duration

  tags = {
    Name        = "${var.role_prefix}ReadOnly"
    Environment = var.environment
    Purpose     = "Read-only access for investigation and monitoring"
    RoleType    = "Human"
  }
}

resource "aws_iam_role_policy_attachment" "readonly_policy" {
  role       = aws_iam_role.readonly.name
  policy_arn = "arn:aws:iam::aws:policy/ReadOnlyAccess"
}

# Billing Role - Financial management and cost control
resource "aws_iam_role" "billing" {
  name               = "${var.role_prefix}Billing"
  assume_role_policy = var.oidc_trust_policy
  max_session_duration = var.billing_session_duration

  tags = {
    Name        = "${var.role_prefix}Billing"
    Environment = var.environment
    Purpose     = "Billing and cost management access"
    RoleType    = "Human"
  }
}

resource "aws_iam_role_policy_attachment" "billing_policy" {
  role       = aws_iam_role.billing.name
  policy_arn = "arn:aws:iam::aws:policy/job-function/Billing"
}

# Additional billing permissions policy
resource "aws_iam_policy" "billing_extended" {
  name        = "${var.role_prefix}BillingExtended"
  description = "Extended billing permissions for cost management"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ce:*",
          "cur:*",
          "budgets:*",
          "aws-portal:*",
          "account:GetAccountInformation",
          "support:*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "billing_extended" {
  role       = aws_iam_role.billing.name
  policy_arn = aws_iam_policy.billing_extended.arn
}

# Security Role - IAM and security management
resource "aws_iam_role" "security" {
  name               = "${var.role_prefix}Security"
  assume_role_policy = var.oidc_trust_policy
  max_session_duration = var.security_session_duration

  tags = {
    Name        = "${var.role_prefix}Security"
    Environment = var.environment
    Purpose     = "Security administration and IAM management"
    RoleType    = "Human"
  }
}

resource "aws_iam_policy" "security_admin" {
  name        = "${var.role_prefix}SecurityAdmin"
  description = "Security administration permissions"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "iam:*",
          "organizations:*",
          "cloudtrail:*",
          "config:*",
          "guardduty:*",
          "securityhub:*",
          "inspector:*",
          "access-analyzer:*",
          "kms:*",
          "secretsmanager:*",
          "ssm:*",
          "logs:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "s3:GetBucketLogging",
          "s3:GetBucketPolicy",
          "s3:GetBucketAcl",
          "s3:GetBucketPublicAccessBlock",
          "s3:GetObject"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "security_admin" {
  role       = aws_iam_role.security.name
  policy_arn = aws_iam_policy.security_admin.arn
}

# Developer Role - Application deployment and management
resource "aws_iam_role" "developer" {
  name               = "${var.role_prefix}Developer"
  assume_role_policy = var.oidc_trust_policy
  max_session_duration = var.developer_session_duration

  tags = {
    Name        = "${var.role_prefix}Developer"
    Environment = var.environment
    Purpose     = "Application development and deployment"
    RoleType    = "Human"
  }
}

resource "aws_iam_policy" "developer_permissions" {
  name        = "${var.role_prefix}DeveloperPermissions"
  description = "Developer permissions for application management"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          # EC2 - Instance management but not networking
          "ec2:RunInstances",
          "ec2:TerminateInstances",
          "ec2:StartInstances", 
          "ec2:StopInstances",
          "ec2:RebootInstances",
          "ec2:DescribeInstances",
          "ec2:DescribeInstanceTypes",
          "ec2:DescribeImages",
          "ec2:DescribeSnapshots",
          "ec2:DescribeVolumes",
          "ec2:CreateTags",
          "ec2:DescribeTags",
          
          # Lambda - Full function management
          "lambda:*",
          
          # S3 - Application data management
          "s3:GetObject",
          "s3:PutObject",
          "s3:DeleteObject",
          "s3:ListBucket",
          "s3:GetBucketLocation",
          "s3:CreateBucket",
          "s3:DeleteBucket",
          "s3:PutBucketPolicy",
          "s3:GetBucketPolicy",
          
          # RDS - Database management
          "rds:*",
          
          # CloudWatch - Monitoring and logs
          "cloudwatch:*",
          "logs:*",
          
          # API Gateway
          "apigateway:*",
          
          # CloudFormation - Application stacks
          "cloudformation:*",
          
          # Application Load Balancer
          "elasticloadbalancing:*",
          
          # Route53 - DNS for applications
          "route53:*",
          
          # Certificate Manager
          "acm:*"
        ]
        Resource = "*"
      },
      {
        Effect = "Deny"
        Action = [
          # Deny VPC and networking changes
          "ec2:CreateVpc",
          "ec2:DeleteVpc",
          "ec2:ModifyVpc*",
          "ec2:CreateSubnet",
          "ec2:DeleteSubnet",
          "ec2:ModifySubnet*",
          "ec2:CreateInternetGateway",
          "ec2:DeleteInternetGateway",
          "ec2:AttachInternetGateway",
          "ec2:DetachInternetGateway",
          "ec2:CreateRouteTable",
          "ec2:DeleteRouteTable",
          "ec2:*Route*",
          "ec2:*SecurityGroup*",
          "ec2:*NetworkAcl*",
          
          # Deny IAM changes
          "iam:*"
        ]
        Resource = "*"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "developer_permissions" {
  role       = aws_iam_role.developer.name
  policy_arn = aws_iam_policy.developer_permissions.arn
}

# Admin Role - Full administrative access (emergency use)
resource "aws_iam_role" "admin" {
  name               = "${var.role_prefix}Admin"
  assume_role_policy = var.oidc_trust_policy
  max_session_duration = var.admin_session_duration

  tags = {
    Name        = "${var.role_prefix}Admin"
    Environment = var.environment
    Purpose     = "Full administrative access (emergency use only)"
    RoleType    = "Human"
  }
}

resource "aws_iam_role_policy_attachment" "admin_policy" {
  role       = aws_iam_role.admin.name
  policy_arn = "arn:aws:iam::aws:policy/AdministratorAccess"
}

# CI Role - Infrastructure-as-code operations
resource "aws_iam_role" "ci" {
  name               = "${var.role_prefix}CI"
  assume_role_policy = var.oidc_trust_policy
  max_session_duration = var.ci_session_duration

  tags = {
    Name        = "${var.role_prefix}CI"
    Environment = var.environment
    Purpose     = "Infrastructure-as-code and CI/CD operations"
    RoleType    = "Automation"
  }
}

resource "aws_iam_policy" "ci_permissions" {
  name        = "${var.role_prefix}CIPermissions"  
  description = "CI/CD permissions for infrastructure management"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          # Full Terraform/OpenTofu permissions
          "*"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "aws:RequestedRegion" = var.allowed_regions
          }
        }
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "ci_permissions" {
  role       = aws_iam_role.ci.name
  policy_arn = aws_iam_policy.ci_permissions.arn
}

# Break-glass policy for emergency IAM user access to assume roles
resource "aws_iam_policy" "break_glass_assume_roles" {
  name        = "${var.role_prefix}BreakGlassAssumeRoles"
  description = "Emergency policy allowing IAM users to assume OIDC roles"

  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "sts:AssumeRole"
        ]
        Resource = [
          aws_iam_role.readonly.arn,
          aws_iam_role.billing.arn,
          aws_iam_role.security.arn,
          aws_iam_role.developer.arn,
          aws_iam_role.admin.arn,
          aws_iam_role.ci.arn
        ]
        Condition = {
          Bool = {
            "aws:MultiFactorAuthPresent" = "true"
          }
        }
      }
    ]
  })
}