# Sunkworks Panic Button

Emergency cost protection for Sunkworks streaming episodes.

## Features

- **Panic Button Lambda**: Stops all non-essential instances across managed accounts
- **Recovery Lambda**: Restores instances from saved manifests
- **Cross-Account Support**: Operates across AWS Organization member accounts
- **Essential Instance Protection**: Respects `Essential=true` tag
- **Recovery Manifests**: Saves state to S3 for restoration

## Usage

### Activation (Emergency)

```bash
# Via AWS CLI
aws lambda invoke \
  --function-name sunkworks-panic-button \
  --payload '{"dry_run": false}' \
  response.json

# Dry run first
aws lambda invoke \
  --function-name sunkworks-panic-button \
  --payload '{"dry_run": true}' \
  response.json
```

### Recovery

```bash
aws lambda invoke \
  --function-name sunkworks-panic-recovery \
  --payload '{"manifest_key": "panic-button/recovery-20240115-143022.json"}' \
  response.json
```

## Target Account Setup

Each target account needs this role:

```hcl
resource "aws_iam_role" "sunkworks_panic_button" {
  name = "SunkworksPanicButtonRole"
  
  assume_role_policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Principal = {
          AWS = "arn:aws:iam::MANAGEMENT_ACCOUNT_ID:role/sunkworks-panic-button-role"
        }
        Action = "sts:AssumeRole"
      }
    ]
  })
}

resource "aws_iam_role_policy_attachment" "panic_button" {
  role       = aws_iam_role.sunkworks_panic_button.name
  policy_arn = aws_iam_policy.sunkworks_panic_button_target.arn
}

resource "aws_iam_policy" "sunkworks_panic_button_target" {
  name = "SunkworksPanicButtonTargetPolicy"
  
  policy = jsonencode({
    Version = "2012-10-17"
    Statement = [
      {
        Effect = "Allow"
        Action = [
          "ec2:DescribeInstances",
          "ec2:StopInstances",
          "ec2:StartInstances",
          "autoscaling:DescribeAutoScalingGroups",
          "autoscaling:SuspendProcesses",
          "autoscaling:ResumeProcesses",
          "autoscaling:UpdateAutoScalingGroup"
        ]
        Resource = "*"
      }
    ]
  })
}
```

## Instance Tagging

Instances must be tagged for management:

```hcl
tags = {
  SunkworksManaged = "true"     # Required for panic button to manage
  Essential        = "false"     # Set to "true" to protect from panic button
}
```
