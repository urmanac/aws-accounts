# Sunkworks Multi-Account Architecture

A resilient AWS multi-account architecture designed for the Sunkworks streaming show, with automatic safety rails to handle the inevitable "oops" moments.

## 🏗️ Architecture Overview

```
┌─────────────────────────────────────────────────────────────────┐
│                    AWS Organizations                             │
│                                                                  │
│  ┌──────────────┐  ┌──────────────┐  ┌──────────────┐           │
│  │   Core OU    │  │ Episodes OU  │  │  Archive OU  │           │
│  │              │  │              │  │              │           │
│  │ • Management │  │ • pihole     │  │ (Completed   │           │
│  │ • Security   │  │ • vind       │  │  episodes)   │           │
│  │ • Logging    │  │ • turing     │  │              │           │
│  └──────────────┘  └──────────────┘  └──────────────┘           │
│                           │                                      │
│                    SCPs Applied                                  │
│              ┌────────────┴────────────┐                        │
│              │                         │                        │
│      ┌───────▼───────┐         ┌───────▼───────┐                │
│      │ Deny Root     │         │ Regional      │                │
│      │ Protect Net   │         │ Restrictions  │                │
│      │ Cost Controls │         │ IAM Guards    │                │
│      └───────────────┘         └───────────────┘                │
└─────────────────────────────────────────────────────────────────┘
```

## 🚨 Blast Radius Containment

### Service Control Policies

| SCP | Protection Level | Description |
|-----|------------------|-------------|
| `sunkworks-deny-root` | Organization-wide | Blocks all root account actions |
| `sunkworks-protect-termination` | Episodes OU | Prevents disabling termination protection |
| `sunkworks-protect-network` | Episodes OU | Blocks route table/VPC deletion on tagged resources |
| `sunkworks-protect-s3` | Organization-wide | Prevents deletion of critical S3 buckets |
| `sunkworks-region-restriction` | Episodes OU | Limits resource creation to approved regions |
| `sunkworks-cost-controls` | Episodes OU | Blocks expensive instance types |
| `sunkworks-iam-guardrails` | Organization-wide | Prevents IAM privilege escalation |

### Protected Resource Tagging

Tag resources to protect them from accidental deletion:

```hcl
tags = {
  NetworkProtected       = "true"   # Protects VPC, subnets, route tables
  TerminationProtected   = "true"   # Protects EC2 instances
  BucketProtected        = "true"   # Protects S3 buckets
  SunkworksManaged       = "true"   # Required for panic button management
  Essential              = "true"   # Excludes from panic button suspension
}
```

## 🎬 Episode Isolation

Each Sunkworks episode gets its own isolated AWS account:

```hcl
module "sunkworks_organization" {
  source = "./modules/sunkworks-organization"
  
  email_domain = "example.com"
  
  enable_pihole_account  = true    # EP042
  enable_vind_account    = true    # EP043  
  enable_turing_account  = true    # EP044
  
  pihole_episode_tag     = "EP042-PIHOLE"
  pihole_expiration_date = "2026-03-31"  # Auto-cleanup
  
  episode_budget_limit   = "20"    # $20 max per episode
}
```

### Episode Account Features

- **Isolated VPC**: Each episode has its own VPC (IPv6-only design)
- **Budget Alerts**: 50%, 80%, 100% threshold notifications
- **Auto-Cleanup**: EventBridge rule triggers after expiration date
- **Panic Button Ready**: SunkworksPanicButtonRole pre-deployed

## 🔴 Panic Button

When things go wrong, stop the bleeding:

```bash
# Emergency: Stop all non-essential instances across all episode accounts
aws lambda invoke \
  --function-name sunkworks-panic-button \
  --payload '{"dry_run": false}' \
  response.json

# Test first with dry run
aws lambda invoke \
  --function-name sunkworks-panic-button \
  --payload '{"dry_run": true}' \
  response.json

# Recover from manifest
aws lambda invoke \
  --function-name sunkworks-panic-recovery \
  --payload '{"manifest_key": "panic-button/recovery-20260131-143022.json"}' \
  response.json
```

## 📣 Stream Notifications

Real-time alerts visible to your audience:

```hcl
module "sunkworks_notifications" {
  source = "./modules/sunkworks-notifications"
  
  discord_webhook_url = var.discord_webhook  # Embedded in Discord
  slack_webhook_url   = var.slack_webhook    # Or Slack
  
  enable_terraform_notifications = true
}
```

Events sent to webhooks:
- 🚨 Panic button activation
- 💰 Budget threshold alerts
- 📦 Backup completion/failure
- 🔧 Terraform apply events
- 🔑 Credential rotation alerts

## 🔐 Enhanced MFA

### YubiKey Integration (No typing on camera)

```bash
# Source the enhanced MFA script
source scripts/sunkworks-mfa.sh

# Auto-detect and use YubiKey
sunkworks_mfa sb

# Force specific method
MFA_METHOD=yubikey sunkworks_mfa sb

# Session monitoring for long streams
sunkworks_session_monitor 60  # Check every 60 seconds
```

### Setup YubiKey OATH

```bash
# Install ykman
brew install ykman

# Add AWS credential to YubiKey
ykman oath accounts add aws-sb <your-totp-secret>
ykman oath accounts add aws-prod <your-totp-secret>

# Verify
ykman oath accounts list
```

### Plan B Authentication

```bash
# Source the Plan B script
source scripts/sunkworks-planb.sh

# Auto-try all methods in priority order:
# 1. YubiKey → 2. 1Password → 3. SSO → 4. Manual
sunkworks_authenticate sb

# Pre-stream check
sunkworks_prestream_check
```

### SSO Device Trust

```bash
source scripts/sunkworks-sso.sh

# Configure SSO
export SSO_START_URL="https://your-sso.awsapps.com/start"
sunkworks_sso_configure

# Login (auto-detects home lab IP)
sunkworks_sso_login

# Switch between episode accounts
sunkworks_switch_episode pihole
```

## 💾 Cross-Account Backup

When you delete the wrong S3 bucket:

```hcl
module "sunkworks_backup" {
  source = "./modules/sunkworks-backup"
  
  backup_retention_days    = 30
  enable_cross_region_copy = true
  backup_replica_region    = "eu-west-1"
  
  # Pre-Terraform apply snapshots
  enable_pre_apply_backup = true
  tfstate_bucket_arns = [
    "arn:aws:s3:::my-tfstate-bucket"
  ]
}
```

### Trigger backup before apply

```bash
# Via Makefile
make backup-before-apply ENV=sb

# Or directly
aws lambda invoke \
  --function-name sunkworks-pre-apply-backup \
  --payload '{"resource_arns": ["arn:aws:s3:::my-bucket"]}' \
  response.json
```

## 🔄 Credential Rotation

Automatic rotation when exposure is detected:

```hcl
module "sunkworks_credential_rotation" {
  source = "./modules/sunkworks-credential-rotation"
  
  sns_topic_arn            = module.sunkworks_notifications.sns_topic_arn
  enable_guardduty_trigger = true  # Auto-rotate on GuardDuty findings
}
```

Manual rotation:

```bash
aws lambda invoke \
  --function-name sunkworks-credential-rotation \
  --payload '{"user_name": "terraform-admin"}' \
  response.json
```

## 📁 Module Reference

| Module | Purpose |
|--------|---------|
| `sunkworks-organization` | AWS Organizations, OUs, episode accounts |
| `sunkworks-scps` | Service Control Policies for blast radius |
| `sunkworks-panic-button` | Emergency instance suspension Lambda |
| `sunkworks-episode-factory` | Bootstrap new episode accounts |
| `sunkworks-notifications` | Discord/Slack webhook delivery |
| `sunkworks-backup` | Cross-account S3 and AWS Backup |
| `sunkworks-credential-rotation` | Automatic key rotation on exposure |

## 🚀 Quick Start

1. **Copy example tfvars**:
   ```bash
   cp sunkworks.tfvars.example sunkworks.tfvars
   ```

2. **Configure variables**:
   ```hcl
   sunkworks_email_domain       = "your-domain.com"
   sunkworks_management_account_id = "123456789012"
   sunkworks_discord_webhook    = "https://discord.com/api/webhooks/..."
   sunkworks_budget_emails      = ["your-email@example.com"]
   ```

3. **Apply**:
   ```bash
   tofu plan -var-file=sunkworks.tfvars
   tofu apply -var-file=sunkworks.tfvars
   ```

4. **Setup MFA scripts**:
   ```bash
   source scripts/sunkworks-mfa.sh
   source scripts/sunkworks-planb.sh
   source scripts/sunkworks-sso.sh
   ```

## 🏷️ Tagging Convention

All Sunkworks resources use consistent tags:

```hcl
tags = {
  Episode          = "EP042-PIHOLE"      # Episode identifier
  SunkworksManaged = "true"              # Managed by Sunkworks infra
  CostCenter       = "sunkworks-streaming"
  ExpirationDate   = "2026-03-31"        # For auto-cleanup
}
```

## 📝 Environment Files

Required `.env` files for MFA:

```bash
# .env.sb
ACCOUNT_ID=123456789012
MFA_DEVICE_NAME=my-yubikey
OP_VAULT_ITEM=op://Vault/AWS-SB/one-time password?attribute=otp

# .env.prod  
ACCOUNT_ID=987654321098
MFA_DEVICE_NAME=my-yubikey
OP_VAULT_ITEM=op://Vault/AWS-Prod/one-time password?attribute=otp
```

## 🎥 Pre-Stream Checklist

```bash
# 1. Run pre-stream check
sunkworks_prestream_check

# 2. Verify YubiKey is connected
ykman list

# 3. Test authentication
sunkworks_mfa sb

# 4. Check session status
sunkworks_session_check

# 5. Start session monitor (in background terminal)
sunkworks_session_monitor 60 &
```
