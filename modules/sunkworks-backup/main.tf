# =============================================================================
# Sunkworks Cross-Account Backup - S3 Bucket Replication
# =============================================================================
# When you delete the wrong S3 bucket live - this saves you.
# Cross-account replication with point-in-time recovery.
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
# Backup Vault in Backup Account
# -----------------------------------------------------------------------------

resource "aws_backup_vault" "sunkworks_central" {
  name = "sunkworks-central-backup-vault"
  
  tags = {
    Name             = "sunkworks-central-vault"
    Purpose          = "Cross-account backup destination"
    SunkworksManaged = "true"
  }
}

# Vault lock for immutable backups (ransomware protection)
resource "aws_backup_vault_lock_configuration" "sunkworks_central" {
  count = var.enable_vault_lock ? 1 : 0
  
  backup_vault_name   = aws_backup_vault.sunkworks_central.name
  min_retention_days  = var.vault_lock_min_retention
  max_retention_days  = var.vault_lock_max_retention
  changeable_for_days = var.vault_lock_changeable_days  # Grace period before lock becomes immutable
}

# -----------------------------------------------------------------------------
# IAM Role for Cross-Account Backup
# -----------------------------------------------------------------------------

resource "aws_iam_role" "sunkworks_backup" {
  name = "SunkworksCrossAccountBackupRole"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "backup.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
  
  tags = {
    Name             = "SunkworksCrossAccountBackupRole"
    SunkworksManaged = "true"
  }
}

resource "aws_iam_role_policy_attachment" "sunkworks_backup" {
  role       = aws_iam_role.sunkworks_backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForBackup"
}

resource "aws_iam_role_policy_attachment" "sunkworks_backup_s3" {
  role       = aws_iam_role.sunkworks_backup.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Backup"
}

resource "aws_iam_role_policy_attachment" "sunkworks_restore" {
  role       = aws_iam_role.sunkworks_backup.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSBackupServiceRolePolicyForRestores"
}

resource "aws_iam_role_policy_attachment" "sunkworks_restore_s3" {
  role       = aws_iam_role.sunkworks_backup.name
  policy_arn = "arn:aws:iam::aws:policy/AWSBackupServiceRolePolicyForS3Restore"
}

# -----------------------------------------------------------------------------
# Backup Plan - Daily backups with cross-region copy
# -----------------------------------------------------------------------------

resource "aws_backup_plan" "sunkworks_daily" {
  name = "sunkworks-daily-backup-plan"
  
  rule {
    rule_name         = "daily-backup"
    target_vault_name = aws_backup_vault.sunkworks_central.name
    schedule          = "cron(0 5 ? * * *)"  # Daily at 5 AM UTC
    
    lifecycle {
      delete_after = var.backup_retention_days
    }
    
    # Cross-region copy for disaster recovery
    dynamic "copy_action" {
      for_each = var.enable_cross_region_copy ? [1] : []
      content {
        destination_vault_arn = "arn:aws:backup:${var.backup_replica_region}:${data.aws_caller_identity.current.account_id}:backup-vault:sunkworks-vault-replica"
        
        lifecycle {
          delete_after = var.backup_retention_days
        }
      }
    }
  }
  
  # Pre-terraform-apply backup rule
  rule {
    rule_name         = "pre-apply-backup"
    target_vault_name = aws_backup_vault.sunkworks_central.name
    
    lifecycle {
      delete_after = 7  # Keep for 1 week
    }
  }
  
  tags = {
    Name             = "sunkworks-daily-backup"
    SunkworksManaged = "true"
  }
}

data "aws_caller_identity" "current" {}

# -----------------------------------------------------------------------------
# Backup Selection - What to backup
# -----------------------------------------------------------------------------

resource "aws_backup_selection" "sunkworks_episode_resources" {
  name         = "sunkworks-episode-resources"
  plan_id      = aws_backup_plan.sunkworks_daily.id
  iam_role_arn = aws_iam_role.sunkworks_backup.arn
  
  # Backup resources with Episode tag
  selection_tag {
    type  = "STRINGEQUALS"
    key   = "Episode"
    value = "*"
  }
  
  # Also backup by SunkworksManaged tag
  selection_tag {
    type  = "STRINGEQUALS"
    key   = "SunkworksManaged"
    value = "true"
  }
}

# Backup tfstate buckets explicitly
resource "aws_backup_selection" "sunkworks_tfstate" {
  name         = "sunkworks-tfstate-backup"
  plan_id      = aws_backup_plan.sunkworks_daily.id
  iam_role_arn = aws_iam_role.sunkworks_backup.arn
  
  resources = var.tfstate_bucket_arns
}

# -----------------------------------------------------------------------------
# S3 Replication Bucket (for immediate S3 backup)
# -----------------------------------------------------------------------------

resource "aws_s3_bucket" "sunkworks_backup_replica" {
  bucket = "sunkworks-backup-replica-${data.aws_caller_identity.current.account_id}"
  
  tags = {
    Name             = "sunkworks-backup-replica"
    Purpose          = "Cross-account S3 replication destination"
    SunkworksManaged = "true"
  }
}

resource "aws_s3_bucket_versioning" "sunkworks_backup_replica" {
  bucket = aws_s3_bucket.sunkworks_backup_replica.id
  
  versioning_configuration {
    status = "Enabled"
  }
}

resource "aws_s3_bucket_lifecycle_configuration" "sunkworks_backup_replica" {
  bucket = aws_s3_bucket.sunkworks_backup_replica.id
  
  rule {
    id     = "expire-old-versions"
    status = "Enabled"
    
    noncurrent_version_expiration {
      noncurrent_days = var.s3_version_retention_days
    }
    
    abort_incomplete_multipart_upload {
      days_after_initiation = 7
    }
  }
  
  rule {
    id     = "transition-to-glacier"
    status = var.enable_glacier_transition ? "Enabled" : "Disabled"
    
    transition {
      days          = 30
      storage_class = "GLACIER"
    }
    
    noncurrent_version_transition {
      noncurrent_days = 7
      storage_class   = "GLACIER"
    }
  }
}

# Bucket policy allowing cross-account replication
resource "aws_s3_bucket_policy" "sunkworks_backup_replica" {
  bucket = aws_s3_bucket.sunkworks_backup_replica.id
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowCrossAccountReplication"
        Effect = "Allow"
        Principal = {
          AWS = [
            for account_id in var.source_account_ids :
            "arn:aws:iam::${account_id}:root"
          ]
        }
        Action = [
          "s3:ReplicateObject",
          "s3:ReplicateDelete",
          "s3:ReplicateTags",
          "s3:ObjectOwnerOverrideToBucketOwner"
        ]
        Resource = "${aws_s3_bucket.sunkworks_backup_replica.arn}/*"
      },
      {
        Sid    = "AllowVersioning"
        Effect = "Allow"
        Principal = {
          AWS = [
            for account_id in var.source_account_ids :
            "arn:aws:iam::${account_id}:root"
          ]
        }
        Action = [
          "s3:GetBucketVersioning",
          "s3:PutBucketVersioning"
        ]
        Resource = aws_s3_bucket.sunkworks_backup_replica.arn
      }
    ]
  })
}

# -----------------------------------------------------------------------------
# Pre-Terraform Apply Automation
# -----------------------------------------------------------------------------

# Lambda to trigger backup before terraform apply
data "archive_file" "sunkworks_pre_apply_backup" {
  type        = "zip"
  output_path = "${path.module}/lambda/sunkworks_pre_apply_backup.zip"
  
  source {
    content  = <<-PYTHON
import boto3
import json
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Trigger backup before Terraform apply for state snapshotting.
    """
    
    backup = boto3.client('backup')
    
    # Get resources to backup from event or environment
    resources = event.get('resource_arns', json.loads(os.environ.get('DEFAULT_RESOURCE_ARNS', '[]')))
    vault_name = os.environ.get('BACKUP_VAULT_NAME', 'sunkworks-central-backup-vault')
    iam_role_arn = os.environ.get('BACKUP_IAM_ROLE_ARN')
    
    if not resources:
        return {'status': 'skipped', 'reason': 'No resources specified'}
    
    results = []
    
    for resource_arn in resources:
        try:
            response = backup.start_backup_job(
                BackupVaultName=vault_name,
                ResourceArn=resource_arn,
                IamRoleArn=iam_role_arn,
                IdempotencyToken=f"pre-apply-{datetime.utcnow().strftime('%Y%m%d%H%M%S')}-{resource_arn.split(':')[-1][:8]}"
            )
            
            results.append({
                'resource': resource_arn,
                'job_id': response['BackupJobId'],
                'status': 'started'
            })
        except Exception as e:
            results.append({
                'resource': resource_arn,
                'error': str(e),
                'status': 'failed'
            })
    
    return {
        'timestamp': datetime.utcnow().isoformat(),
        'backup_jobs': results
    }
PYTHON
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "sunkworks_pre_apply_backup" {
  count = var.enable_pre_apply_backup ? 1 : 0
  
  function_name = "sunkworks-pre-apply-backup"
  description   = "Trigger backup before Terraform apply"
  
  filename         = data.archive_file.sunkworks_pre_apply_backup.output_path
  source_code_hash = data.archive_file.sunkworks_pre_apply_backup.output_base64sha256
  
  handler = "lambda_function.lambda_handler"
  runtime = "python3.11"
  timeout = 60
  
  role = aws_iam_role.sunkworks_pre_apply_backup[0].arn
  
  environment {
    variables = {
      BACKUP_VAULT_NAME    = aws_backup_vault.sunkworks_central.name
      BACKUP_IAM_ROLE_ARN  = aws_iam_role.sunkworks_backup.arn
      DEFAULT_RESOURCE_ARNS = jsonencode(var.tfstate_bucket_arns)
    }
  }
  
  tags = {
    Name             = "sunkworks-pre-apply-backup"
    SunkworksManaged = "true"
  }
}

resource "aws_iam_role" "sunkworks_pre_apply_backup" {
  count = var.enable_pre_apply_backup ? 1 : 0
  
  name = "sunkworks-pre-apply-backup-role"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          Service = "lambda.amazonaws.com"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_policy" "sunkworks_pre_apply_backup" {
  count = var.enable_pre_apply_backup ? 1 : 0
  
  name = "sunkworks-pre-apply-backup-policy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "logs:CreateLogGroup",
          "logs:CreateLogStream",
          "logs:PutLogEvents"
        ]
        Resource = "arn:aws:logs:*:*:*"
      },
      {
        Effect = "Allow"
        Action = [
          "backup:StartBackupJob"
        ]
        Resource = "*"
      },
      {
        Effect = "Allow"
        Action = [
          "iam:PassRole"
        ]
        Resource = aws_iam_role.sunkworks_backup.arn
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sunkworks_pre_apply_backup" {
  count = var.enable_pre_apply_backup ? 1 : 0
  
  role       = aws_iam_role.sunkworks_pre_apply_backup[0].name
  policy_arn = aws_iam_policy.sunkworks_pre_apply_backup[0].arn
}
