# =============================================================================
# Sunkworks Notifications - Discord/Slack Webhooks for Stream Alerts
# =============================================================================
# Real-time notifications of account-wide changes visible to stream audience.
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
# SNS Topic for Sunkworks Events
# -----------------------------------------------------------------------------

resource "aws_sns_topic" "sunkworks_alerts" {
  name = "sunkworks-stream-alerts"
  
  tags = {
    Name             = "sunkworks-stream-alerts"
    SunkworksManaged = "true"
  }
}

# -----------------------------------------------------------------------------
# Lambda for Webhook Delivery (Discord/Slack)
# -----------------------------------------------------------------------------

data "archive_file" "sunkworks_webhook" {
  type        = "zip"
  output_path = "${path.module}/lambda/sunkworks_webhook.zip"
  
  source {
    content  = <<-PYTHON
import json
import os
import urllib.request
import urllib.error
from datetime import datetime

def lambda_handler(event, context):
    """
    Sunkworks Stream Notification Handler
    
    Receives SNS events and forwards to Discord/Slack webhooks
    for audience-visible alerts during live streams.
    """
    
    discord_webhook = os.environ.get('DISCORD_WEBHOOK_URL')
    slack_webhook = os.environ.get('SLACK_WEBHOOK_URL')
    
    results = {'discord': None, 'slack': None, 'errors': []}
    
    for record in event.get('Records', []):
        try:
            sns_message = record['Sns']['Message']
            subject = record['Sns'].get('Subject', 'Sunkworks Alert')
            
            # Try to parse as JSON, fall back to plain text
            try:
                message_data = json.loads(sns_message)
            except json.JSONDecodeError:
                message_data = {'message': sns_message}
            
            # Format message based on event type
            formatted = format_message(subject, message_data)
            
            # Send to Discord
            if discord_webhook:
                discord_payload = create_discord_payload(subject, formatted)
                send_webhook(discord_webhook, discord_payload)
                results['discord'] = 'sent'
            
            # Send to Slack
            if slack_webhook:
                slack_payload = create_slack_payload(subject, formatted)
                send_webhook(slack_webhook, slack_payload)
                results['slack'] = 'sent'
                
        except Exception as e:
            results['errors'].append(str(e))
    
    return results

def format_message(subject, data):
    """Format the message for display"""
    if isinstance(data, dict):
        # Check for known event types
        if 'stopped_instances' in data:
            # Panic button event
            return format_panic_button(data)
        elif 'backup_job_id' in data:
            # Backup event
            return format_backup_event(data)
        elif 'budget_amount' in data:
            # Budget alert
            return format_budget_alert(data)
        else:
            # Generic event
            return json.dumps(data, indent=2)
    return str(data)

def format_panic_button(data):
    """Format panic button notification"""
    stopped = len(data.get('stopped_instances', []))
    suspended = len(data.get('suspended_asgs', []))
    is_dry_run = data.get('dry_run', False)
    
    return f"""**Instances Stopped:** {stopped}
**ASGs Suspended:** {suspended}
**Mode:** {'DRY RUN' if is_dry_run else 'LIVE'}
**Manifest:** {data.get('manifest_location', 'N/A')}"""

def format_backup_event(data):
    """Format backup event notification"""
    return f"""**Job ID:** {data.get('backup_job_id')}
**Resource:** {data.get('resource_arn', 'Unknown')}
**Status:** {data.get('status', 'Unknown')}"""

def format_budget_alert(data):
    """Format budget alert notification"""
    return f"""**Budget:** {data.get('budget_name')}
**Current Spend:** ${data.get('current_spend', '0')}
**Limit:** ${data.get('budget_amount', '20')}
**Threshold:** {data.get('threshold_percentage', '100')}%"""

def create_discord_payload(subject, message):
    """Create Discord webhook payload with embed"""
    
    # Color based on subject
    if 'PANIC' in subject.upper():
        color = 16711680  # Red
        emoji = "🚨"
    elif 'BUDGET' in subject.upper():
        color = 16776960  # Yellow
        emoji = "💰"
    elif 'BACKUP' in subject.upper():
        color = 65280  # Green
        emoji = "📦"
    else:
        color = 3447003  # Blue
        emoji = "📢"
    
    return {
        "embeds": [{
            "title": f"{emoji} {subject}",
            "description": message,
            "color": color,
            "timestamp": datetime.utcnow().isoformat() + "Z",
            "footer": {
                "text": "Sunkworks Stream Alert"
            },
            "author": {
                "name": "Sunkworks AWS",
                "icon_url": "https://a0.awsstatic.com/libra-css/images/logos/aws_logo_smile_1200x630.png"
            }
        }]
    }

def create_slack_payload(subject, message):
    """Create Slack webhook payload with rich formatting"""
    
    # Emoji based on subject
    if 'PANIC' in subject.upper():
        emoji = ":rotating_light:"
        color = "danger"
    elif 'BUDGET' in subject.upper():
        emoji = ":money_with_wings:"
        color = "warning"
    elif 'BACKUP' in subject.upper():
        emoji = ":package:"
        color = "good"
    else:
        emoji = ":loudspeaker:"
        color = "#3AA3E3"
    
    return {
        "attachments": [{
            "color": color,
            "blocks": [
                {
                    "type": "header",
                    "text": {
                        "type": "plain_text",
                        "text": f"{emoji} {subject}"
                    }
                },
                {
                    "type": "section",
                    "text": {
                        "type": "mrkdwn",
                        "text": message.replace('**', '*')  # Slack uses single asterisks
                    }
                },
                {
                    "type": "context",
                    "elements": [
                        {
                            "type": "mrkdwn",
                            "text": f"_Sunkworks Stream Alert • {datetime.utcnow().strftime('%Y-%m-%d %H:%M:%S')} UTC_"
                        }
                    ]
                }
            ]
        }]
    }

def send_webhook(url, payload):
    """Send payload to webhook URL"""
    data = json.dumps(payload).encode('utf-8')
    req = urllib.request.Request(
        url,
        data=data,
        headers={'Content-Type': 'application/json'}
    )
    
    try:
        with urllib.request.urlopen(req) as response:
            return response.read()
    except urllib.error.HTTPError as e:
        print(f"Webhook error: {e.code} - {e.read().decode()}")
        raise
PYTHON
    filename = "lambda_function.py"
  }
}

resource "aws_lambda_function" "sunkworks_webhook" {
  function_name = "sunkworks-stream-notifications"
  description   = "Forward Sunkworks events to Discord/Slack"
  
  filename         = data.archive_file.sunkworks_webhook.output_path
  source_code_hash = data.archive_file.sunkworks_webhook.output_base64sha256
  
  handler = "lambda_function.lambda_handler"
  runtime = "python3.11"
  timeout = 30
  
  role = aws_iam_role.sunkworks_webhook.arn
  
  environment {
    variables = {
      DISCORD_WEBHOOK_URL = var.discord_webhook_url
      SLACK_WEBHOOK_URL   = var.slack_webhook_url
    }
  }
  
  tags = {
    Name             = "sunkworks-stream-notifications"
    SunkworksManaged = "true"
  }
}

# -----------------------------------------------------------------------------
# IAM Role for Webhook Lambda
# -----------------------------------------------------------------------------

resource "aws_iam_role" "sunkworks_webhook" {
  name = "sunkworks-webhook-lambda-role"
  
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

resource "aws_iam_role_policy_attachment" "sunkworks_webhook_logs" {
  role       = aws_iam_role.sunkworks_webhook.name
  policy_arn = "arn:aws:iam::aws:policy/service-role/AWSLambdaBasicExecutionRole"
}

# -----------------------------------------------------------------------------
# SNS Subscription to Lambda
# -----------------------------------------------------------------------------

resource "aws_sns_topic_subscription" "sunkworks_webhook" {
  topic_arn = aws_sns_topic.sunkworks_alerts.arn
  protocol  = "lambda"
  endpoint  = aws_lambda_function.sunkworks_webhook.arn
}

resource "aws_lambda_permission" "sunkworks_webhook_sns" {
  statement_id  = "AllowSNSInvoke"
  action        = "lambda:InvokeFunction"
  function_name = aws_lambda_function.sunkworks_webhook.function_name
  principal     = "sns.amazonaws.com"
  source_arn    = aws_sns_topic.sunkworks_alerts.arn
}

# -----------------------------------------------------------------------------
# CloudWatch Log Group
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_log_group" "sunkworks_webhook" {
  name              = "/aws/lambda/${aws_lambda_function.sunkworks_webhook.function_name}"
  retention_in_days = 7
  
  tags = {
    Name             = "sunkworks-webhook-logs"
    SunkworksManaged = "true"
  }
}

# -----------------------------------------------------------------------------
# EventBridge Rule for Terraform Apply Events
# -----------------------------------------------------------------------------

resource "aws_cloudwatch_event_rule" "sunkworks_terraform_events" {
  count = var.enable_terraform_notifications ? 1 : 0
  
  name        = "sunkworks-terraform-changes"
  description = "Capture CloudTrail events for Terraform applies"
  
  event_pattern = jsonencode({
    source      = ["aws.cloudtrail"]
    detail-type = ["AWS API Call via CloudTrail"]
    detail = {
      eventSource = [
        "ec2.amazonaws.com",
        "iam.amazonaws.com",
        "s3.amazonaws.com",
        "lambda.amazonaws.com",
        "rds.amazonaws.com"
      ]
      eventName = [
        { prefix = "Create" },
        { prefix = "Delete" },
        { prefix = "Modify" },
        { prefix = "Update" }
      ]
      userIdentity = {
        sessionContext = {
          sessionIssuer = {
            userName = var.terraform_role_names
          }
        }
      }
    }
  })
  
  tags = {
    Name             = "sunkworks-terraform-events"
    SunkworksManaged = "true"
  }
}

resource "aws_cloudwatch_event_target" "sunkworks_terraform_to_sns" {
  count = var.enable_terraform_notifications ? 1 : 0
  
  rule      = aws_cloudwatch_event_rule.sunkworks_terraform_events[0].name
  target_id = "send-to-sns"
  arn       = aws_sns_topic.sunkworks_alerts.arn
  
  input_transformer {
    input_paths = {
      eventName   = "$.detail.eventName"
      eventSource = "$.detail.eventSource"
      sourceIP    = "$.detail.sourceIPAddress"
      userAgent   = "$.detail.userAgent"
      region      = "$.region"
    }
    input_template = "\"Terraform applied: <eventName> via <eventSource> in <region> from <sourceIP>\""
  }
}

# -----------------------------------------------------------------------------
# SNS Topic Policy for EventBridge
# -----------------------------------------------------------------------------

resource "aws_sns_topic_policy" "sunkworks_alerts" {
  arn = aws_sns_topic.sunkworks_alerts.arn
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Sid    = "AllowEventBridge"
        Effect = "Allow"
        Principal = {
          Service = "events.amazonaws.com"
        }
        Action   = "sns:Publish"
        Resource = aws_sns_topic.sunkworks_alerts.arn
      }
    ]
  })
}
