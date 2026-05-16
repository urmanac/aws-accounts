# =============================================================================
# Sunkworks Panic Button - Emergency Instance Suspension
# =============================================================================
# "The Button" - When things go wrong during a live stream, this Lambda
# suspends all non-essential instances across accounts to stop bleeding costs.
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
# Lambda Function - Panic Button
# -----------------------------------------------------------------------------

data "archive_file" "sunkworks_panic_button" {
  type        = "zip"
  output_path = "${path.module}/lambda/sunkworks_panic_button.zip"
  
  source {
    content  = <<-PYTHON
import boto3
import json
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Sunkworks Panic Button - Emergency instance suspension
    
    This function:
    1. Stops all running instances tagged with SunkworksManaged=true
    2. Optionally suspends Auto Scaling Groups
    3. Sends notifications via SNS
    4. Creates a recovery manifest for later restoration
    """
    
    print(f"🚨 PANIC BUTTON ACTIVATED at {datetime.utcnow().isoformat()}")
    
    # Configuration
    dry_run = event.get('dry_run', False)
    target_accounts = json.loads(os.environ.get('TARGET_ACCOUNTS', '[]'))
    excluded_instance_ids = json.loads(os.environ.get('EXCLUDED_INSTANCES', '[]'))
    sns_topic_arn = os.environ.get('SNS_TOPIC_ARN')
    s3_bucket = os.environ.get('MANIFEST_BUCKET')
    
    results = {
        'timestamp': datetime.utcnow().isoformat(),
        'dry_run': dry_run,
        'stopped_instances': [],
        'suspended_asgs': [],
        'skipped_instances': [],
        'errors': []
    }
    
    # Get STS for cross-account access
    sts = boto3.client('sts')
    
    for account_id in target_accounts:
        try:
            # Assume role in target account
            assumed = sts.assume_role(
                RoleArn=f"arn:aws:iam::{account_id}:role/SunkworksPanicButtonRole",
                RoleSessionName="panic-button-execution"
            )
            
            creds = assumed['Credentials']
            
            # Create EC2 client for target account
            ec2 = boto3.client(
                'ec2',
                aws_access_key_id=creds['AccessKeyId'],
                aws_secret_access_key=creds['SecretAccessKey'],
                aws_session_token=creds['SessionToken']
            )
            
            # Find running Sunkworks instances
            response = ec2.describe_instances(
                Filters=[
                    {'Name': 'instance-state-name', 'Values': ['running']},
                    {'Name': 'tag:SunkworksManaged', 'Values': ['true']}
                ]
            )
            
            instances_to_stop = []
            for reservation in response['Reservations']:
                for instance in reservation['Instances']:
                    instance_id = instance['InstanceId']
                    
                    # Check if instance is in exclusion list
                    if instance_id in excluded_instance_ids:
                        results['skipped_instances'].append({
                            'account_id': account_id,
                            'instance_id': instance_id,
                            'reason': 'In exclusion list'
                        })
                        continue
                    
                    # Check for Essential tag
                    tags = {t['Key']: t['Value'] for t in instance.get('Tags', [])}
                    if tags.get('Essential', '').lower() == 'true':
                        results['skipped_instances'].append({
                            'account_id': account_id,
                            'instance_id': instance_id,
                            'reason': 'Tagged as Essential'
                        })
                        continue
                    
                    instances_to_stop.append(instance_id)
            
            # Stop instances
            if instances_to_stop:
                if not dry_run:
                    ec2.stop_instances(InstanceIds=instances_to_stop)
                
                for instance_id in instances_to_stop:
                    results['stopped_instances'].append({
                        'account_id': account_id,
                        'instance_id': instance_id,
                        'dry_run': dry_run
                    })
                    print(f"{'[DRY RUN] ' if dry_run else ''}Stopped {instance_id} in {account_id}")
            
            # Suspend Auto Scaling Groups
            autoscaling = boto3.client(
                'autoscaling',
                aws_access_key_id=creds['AccessKeyId'],
                aws_secret_access_key=creds['SecretAccessKey'],
                aws_session_token=creds['SessionToken']
            )
            
            asgs = autoscaling.describe_auto_scaling_groups(
                Filters=[
                    {'Name': 'tag:SunkworksManaged', 'Values': ['true']}
                ]
            )
            
            for asg in asgs.get('AutoScalingGroups', []):
                asg_name = asg['AutoScalingGroupName']
                
                # Skip essential ASGs
                tags = {t['Key']: t['Value'] for t in asg.get('Tags', [])}
                if tags.get('Essential', '').lower() == 'true':
                    continue
                
                if not dry_run:
                    # Suspend all scaling processes
                    autoscaling.suspend_processes(AutoScalingGroupName=asg_name)
                    
                    # Set desired capacity to 0
                    autoscaling.update_auto_scaling_group(
                        AutoScalingGroupName=asg_name,
                        MinSize=0,
                        DesiredCapacity=0
                    )
                
                results['suspended_asgs'].append({
                    'account_id': account_id,
                    'asg_name': asg_name,
                    'previous_desired': asg['DesiredCapacity'],
                    'dry_run': dry_run
                })
                print(f"{'[DRY RUN] ' if dry_run else ''}Suspended ASG {asg_name} in {account_id}")
                
        except Exception as e:
            error_msg = f"Error processing account {account_id}: {str(e)}"
            print(f"❌ {error_msg}")
            results['errors'].append(error_msg)
    
    # Save recovery manifest to S3
    if s3_bucket and not dry_run:
        s3 = boto3.client('s3')
        manifest_key = f"panic-button/recovery-{datetime.utcnow().strftime('%Y%m%d-%H%M%S')}.json"
        s3.put_object(
            Bucket=s3_bucket,
            Key=manifest_key,
            Body=json.dumps(results, indent=2),
            ContentType='application/json'
        )
        results['manifest_location'] = f"s3://{s3_bucket}/{manifest_key}"
        print(f"📝 Recovery manifest saved to {results['manifest_location']}")
    
    # Send SNS notification
    if sns_topic_arn:
        sns = boto3.client('sns')
        
        subject = "🚨 SUNKWORKS PANIC BUTTON ACTIVATED" if not dry_run else "🧪 Panic Button DRY RUN"
        
        message = f"""
Sunkworks Panic Button Activation Report
=========================================
Time: {results['timestamp']}
Mode: {'DRY RUN' if dry_run else 'LIVE EXECUTION'}

Instances Stopped: {len(results['stopped_instances'])}
ASGs Suspended: {len(results['suspended_asgs'])}
Instances Skipped: {len(results['skipped_instances'])}
Errors: {len(results['errors'])}

{'Recovery manifest: ' + results.get('manifest_location', 'N/A') if not dry_run else 'No manifest (dry run)'}

Stopped Instances:
{json.dumps(results['stopped_instances'], indent=2)}

Errors:
{json.dumps(results['errors'], indent=2) if results['errors'] else 'None'}
"""
        
        sns.publish(
            TopicArn=sns_topic_arn,
            Subject=subject,
            Message=message
        )
        print("📧 Notification sent via SNS")
    
    print(f"✅ Panic button execution complete")
    return results
PYTHON
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "sunkworks_panic_button" {
  function_name = "sunkworks-panic-button"
  description   = "Emergency instance suspension for cost protection"
  
  filename         = data.archive_file.sunkworks_panic_button.output_path
  source_code_hash = data.archive_file.sunkworks_panic_button.output_base64sha256
  
  handler = "lambda_function.lambda_handler"
  runtime = "python3.11"
  timeout = 300
  
  role = aws_iam_role.sunkworks_panic_button.arn
  
  environment {
    variables = {
      TARGET_ACCOUNTS    = jsonencode(var.target_account_ids)
      EXCLUDED_INSTANCES = jsonencode(var.excluded_instance_ids)
      SNS_TOPIC_ARN      = var.notification_sns_topic_arn
      MANIFEST_BUCKET    = var.manifest_bucket_name
    }
  }
  
  tags = {
    Name    = "sunkworks-panic-button"
    Purpose = "Emergency cost protection"
  }
}

# -----------------------------------------------------------------------------
# IAM Role for Panic Button Lambda
# -----------------------------------------------------------------------------

resource "aws_iam_role" "sunkworks_panic_button" {
  name = "sunkworks-panic-button-role"
  
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

resource "aws_iam_policy" "sunkworks_panic_button" {
  name        = "sunkworks-panic-button-policy"
  description = "Permissions for panic button Lambda"
  
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
          "sts:AssumeRole"
        ]
        Resource = [
          for account_id in var.target_account_ids :
          "arn:aws:iam::${account_id}:role/SunkworksPanicButtonRole"
        ]
      },
      {
        Effect = "Allow"
        Action = [
          "sns:Publish"
        ]
        Resource = var.notification_sns_topic_arn != null ? [var.notification_sns_topic_arn] : ["*"]
      },
      {
        Effect = "Allow"
        Action = [
          "s3:PutObject"
        ]
        Resource = var.manifest_bucket_name != null ? ["arn:aws:s3:::${var.manifest_bucket_name}/panic-button/*"] : ["*"]
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "sunkworks_panic_button" {
  role       = aws_iam_role.sunkworks_panic_button.name
  policy_arn = aws_iam_policy.sunkworks_panic_button.arn
}

# -----------------------------------------------------------------------------
# Lambda Function URL - Quick access during streams
# -----------------------------------------------------------------------------

resource "aws_lambda_function_url" "sunkworks_panic_button" {
  count = var.enable_function_url ? 1 : 0
  
  function_name      = aws_lambda_function.sunkworks_panic_button.function_name
  authorization_type = "AWS_IAM"
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "sunkworks_panic_button" {
  name              = "/aws/lambda/${aws_lambda_function.sunkworks_panic_button.function_name}"
  retention_in_days = 30
  
  tags = {
    Name = "sunkworks-panic-button-logs"
  }
}

# -----------------------------------------------------------------------------
# Recovery Lambda - Restore instances from manifest
# -----------------------------------------------------------------------------

data "archive_file" "sunkworks_panic_recovery" {
  type        = "zip"
  output_path = "${path.module}/lambda/sunkworks_panic_recovery.zip"
  
  source {
    content  = <<-PYTHON
import boto3
import json
import os
from datetime import datetime

def lambda_handler(event, context):
    """
    Sunkworks Panic Recovery - Restore instances from manifest
    """
    
    print(f"🔄 PANIC RECOVERY INITIATED at {datetime.utcnow().isoformat()}")
    
    manifest_key = event.get('manifest_key')
    s3_bucket = os.environ.get('MANIFEST_BUCKET')
    
    if not manifest_key or not s3_bucket:
        return {'error': 'manifest_key and MANIFEST_BUCKET required'}
    
    # Load recovery manifest
    s3 = boto3.client('s3')
    response = s3.get_object(Bucket=s3_bucket, Key=manifest_key)
    manifest = json.loads(response['Body'].read().decode('utf-8'))
    
    results = {
        'timestamp': datetime.utcnow().isoformat(),
        'manifest_used': f"s3://{s3_bucket}/{manifest_key}",
        'started_instances': [],
        'resumed_asgs': [],
        'errors': []
    }
    
    sts = boto3.client('sts')
    
    # Group instances by account
    account_instances = {}
    for instance in manifest.get('stopped_instances', []):
        account_id = instance['account_id']
        if account_id not in account_instances:
            account_instances[account_id] = []
        account_instances[account_id].append(instance['instance_id'])
    
    # Start instances in each account
    for account_id, instance_ids in account_instances.items():
        try:
            assumed = sts.assume_role(
                RoleArn=f"arn:aws:iam::{account_id}:role/SunkworksPanicButtonRole",
                RoleSessionName="panic-recovery-execution"
            )
            
            creds = assumed['Credentials']
            ec2 = boto3.client(
                'ec2',
                aws_access_key_id=creds['AccessKeyId'],
                aws_secret_access_key=creds['SecretAccessKey'],
                aws_session_token=creds['SessionToken']
            )
            
            ec2.start_instances(InstanceIds=instance_ids)
            
            for instance_id in instance_ids:
                results['started_instances'].append({
                    'account_id': account_id,
                    'instance_id': instance_id
                })
                print(f"✅ Started {instance_id} in {account_id}")
                
        except Exception as e:
            results['errors'].append(f"Error in {account_id}: {str(e)}")
    
    # Resume ASGs
    for asg_info in manifest.get('suspended_asgs', []):
        account_id = asg_info['account_id']
        asg_name = asg_info['asg_name']
        previous_desired = asg_info.get('previous_desired', 1)
        
        try:
            assumed = sts.assume_role(
                RoleArn=f"arn:aws:iam::{account_id}:role/SunkworksPanicButtonRole",
                RoleSessionName="panic-recovery-execution"
            )
            
            creds = assumed['Credentials']
            autoscaling = boto3.client(
                'autoscaling',
                aws_access_key_id=creds['AccessKeyId'],
                aws_secret_access_key=creds['SecretAccessKey'],
                aws_session_token=creds['SessionToken']
            )
            
            autoscaling.resume_processes(AutoScalingGroupName=asg_name)
            autoscaling.update_auto_scaling_group(
                AutoScalingGroupName=asg_name,
                DesiredCapacity=previous_desired
            )
            
            results['resumed_asgs'].append({
                'account_id': account_id,
                'asg_name': asg_name,
                'restored_capacity': previous_desired
            })
            print(f"✅ Resumed ASG {asg_name} in {account_id}")
            
        except Exception as e:
            results['errors'].append(f"Error resuming ASG {asg_name}: {str(e)}")
    
    print(f"✅ Recovery complete")
    return results
PYTHON
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "sunkworks_panic_recovery" {
  function_name = "sunkworks-panic-recovery"
  description   = "Restore instances after panic button activation"
  
  filename         = data.archive_file.sunkworks_panic_recovery.output_path
  source_code_hash = data.archive_file.sunkworks_panic_recovery.output_base64sha256
  
  handler = "lambda_function.lambda_handler"
  runtime = "python3.11"
  timeout = 300
  
  role = aws_iam_role.sunkworks_panic_button.arn
  
  environment {
    variables = {
      MANIFEST_BUCKET = var.manifest_bucket_name
    }
  }
  
  tags = {
    Name    = "sunkworks-panic-recovery"
    Purpose = "Restore after panic button"
  }
}
