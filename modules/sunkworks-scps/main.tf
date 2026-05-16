# =============================================================================
# Sunkworks Service Control Policies - Blast Radius Containment
# =============================================================================
# These SCPs prevent catastrophic mistakes during live streaming:
# - Block root account usage
# - Prevent termination protection bypass
# - Protect critical networking infrastructure
# - Enforce regional restrictions
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# -----------------------------------------------------------------------------
# SCP: Block Root Account Usage (The "Oh No" Protection)
# -----------------------------------------------------------------------------
resource "aws_organizations_policy" "sunkworks_deny_root" {
  name        = "sunkworks-deny-root-account"
  description = "Prevent root account usage - the 'oh no' protection for Sunkworks"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid       = "DenyRootAccountActions"
        Effect    = "Deny"
        Action    = "*"
        Resource  = "*"
        Condition = {
          StringLike = {
            "aws:PrincipalArn" = "arn:aws:iam::*:root"
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# SCP: Protect Termination Protection (No accidental instance kills)
# -----------------------------------------------------------------------------
resource "aws_organizations_policy" "sunkworks_protect_instances" {
  name        = "sunkworks-protect-termination"
  description = "Prevent disabling termination protection on critical instances"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyDisableTerminationProtection"
        Effect = "Deny"
        Action = [
          "ec2:ModifyInstanceAttribute"
        ]
        Resource = "*"
        Condition = {
          StringEquals = {
            "ec2:Attribute" = "disableApiTermination"
          }
          "ForAnyValue:StringEquals" = {
            "aws:ResourceTag/TerminationProtected" = "true"
          }
        }
      },
      {
        Sid    = "DenyTerminateProtectedInstances"
        Effect = "Deny"
        Action = [
          "ec2:TerminateInstances"
        ]
        Resource = "*"
        Condition = {
          "ForAnyValue:StringEquals" = {
            "aws:ResourceTag/TerminationProtected" = "true"
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# SCP: Network Infrastructure Protection (Subnet isolation protection)
# -----------------------------------------------------------------------------
resource "aws_organizations_policy" "sunkworks_protect_network" {
  name        = "sunkworks-protect-network"
  description = "Prevent deletion of critical networking components during streams"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyRouteTableDeletion"
        Effect = "Deny"
        Action = [
          "ec2:DeleteRouteTable",
          "ec2:DeleteRoute",
          "ec2:ReplaceRoute",
          "ec2:DisassociateRouteTable"
        ]
        Resource = "*"
        Condition = {
          "ForAnyValue:StringEquals" = {
            "aws:ResourceTag/NetworkProtected" = "true"
          }
        }
      },
      {
        Sid    = "DenySubnetDeletion"
        Effect = "Deny"
        Action = [
          "ec2:DeleteSubnet"
        ]
        Resource = "*"
        Condition = {
          "ForAnyValue:StringEquals" = {
            "aws:ResourceTag/NetworkProtected" = "true"
          }
        }
      },
      {
        Sid    = "DenyVPCDeletion"
        Effect = "Deny"
        Action = [
          "ec2:DeleteVpc"
        ]
        Resource = "*"
        Condition = {
          "ForAnyValue:StringEquals" = {
            "aws:ResourceTag/NetworkProtected" = "true"
          }
        }
      },
      {
        Sid    = "DenyInternetGatewayDetach"
        Effect = "Deny"
        Action = [
          "ec2:DetachInternetGateway",
          "ec2:DeleteInternetGateway"
        ]
        Resource = "*"
        Condition = {
          "ForAnyValue:StringEquals" = {
            "aws:ResourceTag/NetworkProtected" = "true"
          }
        }
      },
      {
        Sid    = "DenyNATGatewayDeletion"
        Effect = "Deny"
        Action = [
          "ec2:DeleteNatGateway"
        ]
        Resource = "*"
        Condition = {
          "ForAnyValue:StringEquals" = {
            "aws:ResourceTag/NetworkProtected" = "true"
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# SCP: S3 Deletion Protection (When you delete the wrong bucket live)
# -----------------------------------------------------------------------------
resource "aws_organizations_policy" "sunkworks_protect_s3" {
  name        = "sunkworks-protect-s3-critical"
  description = "Prevent deletion of critical S3 buckets and their contents"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyS3BucketDeletion"
        Effect = "Deny"
        Action = [
          "s3:DeleteBucket",
          "s3:DeleteBucketPolicy"
        ]
        Resource = "*"
        Condition = {
          "ForAnyValue:StringLike" = {
            "s3:ExistingObjectTag/BucketProtected" = "true"
          }
        }
      },
      {
        Sid    = "DenyDeleteCriticalObjects"
        Effect = "Deny"
        Action = [
          "s3:DeleteObject",
          "s3:DeleteObjectVersion"
        ]
        Resource = [
          "arn:aws:s3:::*-tfstate/*",
          "arn:aws:s3:::*-backups/*",
          "arn:aws:s3:::*-critical/*"
        ]
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# SCP: Regional Restriction (Keep experiments contained)
# -----------------------------------------------------------------------------
resource "aws_organizations_policy" "sunkworks_region_restriction" {
  name        = "sunkworks-region-restriction"
  description = "Restrict resource creation to approved regions"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyNonApprovedRegions"
        Effect = "Deny"
        Action = [
          "ec2:RunInstances",
          "ec2:CreateVpc",
          "rds:CreateDBInstance",
          "rds:CreateDBCluster",
          "lambda:CreateFunction",
          "eks:CreateCluster"
        ]
        Resource = "*"
        Condition = {
          StringNotEquals = {
            "aws:RequestedRegion" = var.approved_regions
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# SCP: Episode Cost Controls (Prevent runaway spending)
# -----------------------------------------------------------------------------
resource "aws_organizations_policy" "sunkworks_cost_controls" {
  name        = "sunkworks-cost-controls"
  description = "Prevent expensive resource creation in episode accounts"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyExpensiveInstanceTypes"
        Effect = "Deny"
        Action = [
          "ec2:RunInstances"
        ]
        Resource = "arn:aws:ec2:*:*:instance/*"
        Condition = {
          "ForAnyValue:StringNotLike" = {
            "ec2:InstanceType" = var.allowed_instance_types
          }
        }
      },
      {
        Sid    = "DenyExpensiveRDSInstances"
        Effect = "Deny"
        Action = [
          "rds:CreateDBInstance"
        ]
        Resource = "*"
        Condition = {
          "ForAnyValue:StringNotLike" = {
            "rds:DatabaseClass" = var.allowed_rds_classes
          }
        }
      },
      {
        Sid    = "DenyReservedPurchases"
        Effect = "Deny"
        Action = [
          "ec2:PurchaseReservedInstancesOffering",
          "rds:PurchaseReservedDBInstancesOffering",
          "ec2:PurchaseHostReservation"
        ]
        Resource = "*"
      },
      {
        Sid    = "DenyLargeEBSVolumes"
        Effect = "Deny"
        Action = [
          "ec2:CreateVolume"
        ]
        Resource = "*"
        Condition = {
          NumericGreaterThan = {
            "ec2:VolumeSize" = var.max_ebs_size_gb
          }
        }
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# SCP: IAM Safety Rails (Prevent privilege escalation)
# -----------------------------------------------------------------------------
resource "aws_organizations_policy" "sunkworks_iam_guardrails" {
  name        = "sunkworks-iam-guardrails"
  description = "Prevent IAM privilege escalation and credential exposure"
  type        = "SERVICE_CONTROL_POLICY"

  content = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "DenyIAMUserCreation"
        Effect = "Deny"
        Action = [
          "iam:CreateUser",
          "iam:CreateAccessKey",
          "iam:CreateLoginProfile"
        ]
        Resource = "*"
        Condition = {
          StringNotLike = {
            "aws:PrincipalArn" = [
              "arn:aws:iam::*:role/SunkworksOrganizationRole",
              "arn:aws:iam::*:role/SunkworksAdminRole"
            ]
          }
        }
      },
      {
        Sid    = "DenyModifyCloudTrail"
        Effect = "Deny"
        Action = [
          "cloudtrail:StopLogging",
          "cloudtrail:DeleteTrail",
          "cloudtrail:UpdateTrail"
        ]
        Resource = "*"
        Condition = {
          StringNotLike = {
            "aws:PrincipalArn" = "arn:aws:iam::*:role/SunkworksSecurityRole"
          }
        }
      },
      {
        Sid    = "DenyLeaveOrganization"
        Effect = "Deny"
        Action = [
          "organizations:LeaveOrganization"
        ]
        Resource = "*"
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# SCP Attachments
# -----------------------------------------------------------------------------

# Attach root protection to entire org
resource "aws_organizations_policy_attachment" "deny_root_all" {
  policy_id = aws_organizations_policy.sunkworks_deny_root.id
  target_id = var.organization_root_id
}

# Attach network protection to episodes OU
resource "aws_organizations_policy_attachment" "protect_network_episodes" {
  policy_id = aws_organizations_policy.sunkworks_protect_network.id
  target_id = var.episodes_ou_id
}

# Attach instance protection to episodes OU
resource "aws_organizations_policy_attachment" "protect_instances_episodes" {
  policy_id = aws_organizations_policy.sunkworks_protect_instances.id
  target_id = var.episodes_ou_id
}

# Attach S3 protection to entire org
resource "aws_organizations_policy_attachment" "protect_s3_all" {
  policy_id = aws_organizations_policy.sunkworks_protect_s3.id
  target_id = var.organization_root_id
}

# Attach regional restrictions to episodes OU
resource "aws_organizations_policy_attachment" "region_restriction_episodes" {
  policy_id = aws_organizations_policy.sunkworks_region_restriction.id
  target_id = var.episodes_ou_id
}

# Attach cost controls to episodes OU
resource "aws_organizations_policy_attachment" "cost_controls_episodes" {
  policy_id = aws_organizations_policy.sunkworks_cost_controls.id
  target_id = var.episodes_ou_id
}

# Attach IAM guardrails to entire org
resource "aws_organizations_policy_attachment" "iam_guardrails_all" {
  policy_id = aws_organizations_policy.sunkworks_iam_guardrails.id
  target_id = var.organization_root_id
}
