# =============================================================================
# Sunkworks Credential Rotation - Automated Key Rotation on Exposure
# =============================================================================
# When GitHub Actions detects potential credential exposure, automatically
# rotate the affected credentials and revoke old sessions.
# =============================================================================

terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
    archive = {
      source  = "hashicorp/archive"
      version = "~> 2.0"
    }
  }
}

# -----------------------------------------------------------------------------
# Lambda for Credential Rotation
# -----------------------------------------------------------------------------

data "archive_file" "sunkworks_credential_rotation" {
  type        = "zip"
  output_path = "${path.module}/lambda/sunkworks_credential_rotation.zip"
  
  source {
    content  = <<-PYTHON
import boto3
import json
import os
from datetime import datetime, timedelta

def lambda_handler(event, context):
    """
    Sunkworks Credential Rotation - Automatic rotation on exposure detection
    
    Triggered by:
    - GitHub security alert webhooks
    - GuardDuty findings
    - Manual trigger with user_name parameter
    """
    
    iam = boto3.client('iam')
    sns_topic = os.environ.get('SNS_TOPIC_ARN')
    
    results = {
        'timestamp': datetime.utcnow().isoformat(),
        'rotated_users': [],
        'revoked_sessions': [],
        'errors': []
    }
    
    # Get target users from event
    target_users = []
    
    # From GitHub webhook (secrets scanning)
    if 'github_alert' in event:
        alert = event['github_alert']
        # Parse alert for affected user
        if 'secret_type' in alert and 'aws' in alert['secret_type'].lower():
            # Try to determine which IAM user from the secret
            # This would need customization based on your secret format
            target_users.append(event.get('iam_user', 'unknown'))
    
    # From GuardDuty
    if 'detail' in event and event.get('source') == 'aws.guardduty':
        detail = event['detail']
        # Look for IAM-related findings
        if 'IAM' in detail.get('type', ''):
            # Extract affected principal
            affected = detail.get('resource', {}).get('accessKeyDetails', {})
            if 'userName' in affected:
                target_users.append(affected['userName'])
    
    # From manual trigger
    if 'user_name' in event:
        target_users.append(event['user_name'])
    
    if 'user_names' in event:
        target_users.extend(event['user_names'])
    
    # Remove duplicates
    target_users = list(set(target_users))
    
    if not target_users:
        return {'status': 'skipped', 'reason': 'No target users identified'}
    
    for user_name in target_users:
        try:
            print(f"Processing credential rotation for user: {user_name}")
            
            # 1. List existing access keys
            keys_response = iam.list_access_keys(UserName=user_name)
            old_keys = [k['AccessKeyId'] for k in keys_response['AccessKeyMetadata']]
            
            # 2. Create new access key (if user has less than 2)
            if len(old_keys) < 2:
                new_key = iam.create_access_key(UserName=user_name)
                print(f"Created new access key: {new_key['AccessKey']['AccessKeyId']}")
                
                # Store new key in Secrets Manager
                store_credential_in_secrets_manager(
                    user_name,
                    new_key['AccessKey']['AccessKeyId'],
                    new_key['AccessKey']['SecretAccessKey']
                )
            
            # 3. Deactivate old keys
            for key_id in old_keys:
                iam.update_access_key(
                    UserName=user_name,
                    AccessKeyId=key_id,
                    Status='Inactive'
                )
                print(f"Deactivated access key: {key_id}")
            
            # 4. Revoke all existing sessions (attach deny policy temporarily)
            revoke_policy_name = f"RevokeOldSessions-{user_name}"
            revoke_policy_doc = {
                "Version": "2012-10-17",
                "Statement": [{
                    "Sid": "RevokeOldSessions",
                    "Effect": "Deny",
                    "Action": "*",
                    "Resource": "*",
                    "Condition": {
                        "DateLessThan": {
                            "aws:TokenIssueTime": datetime.utcnow().isoformat() + "Z"
                        }
                    }
                }]
            }
            
            iam.put_user_policy(
                UserName=user_name,
                PolicyName=revoke_policy_name,
                PolicyDocument=json.dumps(revoke_policy_doc)
            )
            
            results['rotated_users'].append({
                'user_name': user_name,
                'old_keys_deactivated': old_keys,
                'sessions_revoked': True
            })
            
            results['revoked_sessions'].append(user_name)
            
        except Exception as e:
            error_msg = f"Error rotating credentials for {user_name}: {str(e)}"
            print(f"ERROR: {error_msg}")
            results['errors'].append(error_msg)
    
    # Send notification
    if sns_topic:
        send_notification(sns_topic, results)
    
    return results

def store_credential_in_secrets_manager(user_name, access_key_id, secret_access_key):
    """Store new credentials in Secrets Manager"""
    sm = boto3.client('secretsmanager')
    
    secret_name = f"sunkworks/iam/{user_name}"
    secret_value = json.dumps({
        'access_key_id': access_key_id,
        'secret_access_key': secret_access_key,
        'rotated_at': datetime.utcnow().isoformat()
    })
    
    try:
        sm.update_secret(
            SecretId=secret_name,
            SecretString=secret_value
        )
    except sm.exceptions.ResourceNotFoundException:
        sm.create_secret(
            Name=secret_name,
            SecretString=secret_value,
            Description=f"Auto-rotated credentials for IAM user {user_name}"
        )

def send_notification(topic_arn, results):
    """Send SNS notification about rotation"""
    sns = boto3.client('sns')
    
    subject = "🔑 Sunkworks Credential Rotation Alert"
    if results['errors']:
        subject = "⚠️ Sunkworks Credential Rotation - Issues Detected"
    
    message = f"""
Credential Rotation Report
==========================
Time: {results['timestamp']}

Users Rotated: {len(results['rotated_users'])}
Sessions Revoked: {len(results['revoked_sessions'])}
Errors: {len(results['errors'])}

Details:
{json.dumps(results, indent=2)}

ACTION REQUIRED:
- Update any systems using these credentials
- New credentials are stored in Secrets Manager
- Monitor for unauthorized access attempts
"""
    
    sns.publish(
        TopicArn=topic_arn,
        Subject=subject,
        Message=message
    )
PYTHON
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "sunkworks_credential_rotation" {
  function_name = "sunkworks-credential-rotation"
  description   = "Automatic credential rotation on exposure detection"
  
  filename         = data.archive_file.sunkworks_credential_rotation.output_path
  source_code_hash = data.archive_file.sunkworks_credential_rotation.output_base64sha256
  
  handler = "lambda_function.lambda_handler"
  runtime = "python3.11"
  timeout = 120
  
  role = aws_iam_role.sunkworks_credential_rotation.arn
  
  environment {
    variables = {
      SNS_TOPIC_ARN = var.sns_topic_arn
    }
  }
  
  tags = {
    Name             = "sunkworks-credential-rotation"
    SunkworksManaged = "true"
  }
}

# -----------------------------------------------------------------------------
# IAM Role for Credential Rotation Lambda
# -----------------------------------------------------------------------------

resource "aws_iam_role" "sunkworks_credential_rotation" {
  name = "sunkworks-credential-rotation-role"
  
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

resource "aws_iam_policy" "sunkworks_credential_rotation" {
  name        = "sunkworks-credential-rotation-policy"
  description = "Permissions for credential rotation Lambda"
  
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
          "iam:ListAccessKeys",
          "iam:CreateAccessKey",
          "iam:UpdateAccessKey",
          "iam:DeleteAccessKey",
          "iam:PutUserPolicy",
          "iam:DeleteUserPolicy"
        ]
        Resource = "arn:aws:iam::*:user/*"
      },
      {
        Effect = "Allow"
        Action = [
          "secretsmanager:CreateSecret",
          "secretsmanager:UpdateSecret",
          "secretsmanager:PutSecretValue"
        ]
        Resource = "arn:aws:secretsmanager:*:*:secret:sunkworks/*"
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.sns_topic_arn != null ? [var.sns_topic_arn] : ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sunkworks_credential_rotation" {
  role       = aws_iam_role.sunkworks_credential_rotation.name
  policy_arn = aws_iam_policy.sunkworks_credential_rotation.arn
}

# -----------------------------------------------------------------------------
# GuardDuty Integration - Trigger on suspicious IAM activity
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "sunkworks_guardduty_iam" {
  count = var.enable_guardduty_trigger ? 1 : 0
  
  name        = "sunkworks-guardduty-iam-findings"
  description = "Trigger credential rotation on GuardDuty IAM findings"
  
  event_pattern = jsonencode({
    source      = ["aws.guardduty"]
    detail-type = ["GuardDuty Finding"]
    detail = {
      type = [
        { prefix = "UnauthorizedAccess:IAM" },
        { prefix = "CredentialAccess:IAM" },
        { prefix = "Stealth:IAM" }
      ]
      severity = [
        { "numeric" = [">", 4] }  # Only medium+ severity
      ]
    }
  })
  
  tags = {
    Name             = "sunkworks-guardduty-iam-trigger"
    SunkworksManaged = "true"
  }
}

resource "aws_cloudwatch_event_target" "sunkworks_guardduty_to_rotation" {
  count = var.enable_guardduty_trigger ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.sunkworks_guardduty_iam[0].name
  target_id = "trigger-credential-rotation"
  arn       = aws_lambda_function.sunkworks_credential_rotation.arn
}

resource "aws_lambda_permission" "sunkworks_guardduty" {
  count = var.enable_guardduty_trigger ? 1 : 0
  
  statement_id  = "AllowGuardDutyInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sunkworks_credential_rotation.function_name
  principal     = "events.amazonaws.com"
  source_arn    = aws_cloudwatch_event_rule.sunkworks_guardduty_iam[0].arn
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "sunkworks_credential_rotation" {
  name              = "/aws/lambda/${aws_lambda_function.sunkworks_credential_rotation.function_name}"
  retention_in_days = 30
  
  tags = {
    Name             = "sunkworks-credential-rotation-logs"
    SunkworksManaged = "true"
  }
}
