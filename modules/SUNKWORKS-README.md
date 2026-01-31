# Sunkworks Modules

Infrastructure modules for the Sunkworks multi-account AWS architecture.

## Core Modules

### sunkworks-organization

Creates the AWS Organizations structure with episode OUs, accounts, tag policies, and backup policies.

```hcl
module "sunkworks_organization" {
  source = "./modules/sunkworks-organization"
  
  email_domain          = "example.com"
  enable_pihole_account = true
  episode_budget_limit  = "20"
}
```

### sunkworks-scps

Service Control Policies for blast radius containment.

```hcl
module "sunkworks_scps" {
  source = "./modules/sunkworks-scps"
  
  organization_root_id = module.org.root_id
  episodes_ou_id       = module.org.episodes_ou_id
  approved_regions     = ["us-east-1", "eu-west-1"]
}
```

### sunkworks-panic-button

Emergency Lambda to suspend all non-essential instances across accounts.

```hcl
module "sunkworks_panic_button" {
  source = "./modules/sunkworks-panic-button"
  
  target_account_ids         = ["123456789012"]
  notification_sns_topic_arn = module.notifications.sns_topic_arn
}
```

### sunkworks-episode-factory

Bootstraps new episode accounts with VPC, IAM roles, and budget alerts.

```hcl
module "sunkworks_episode_factory" {
  source = "./modules/sunkworks-episode-factory"
  
  episode_name          = "pihole"
  episode_tag           = "EP042-PIHOLE"
  management_account_id = "123456789012"
  expiration_date       = "2026-03-31"
}
```

### sunkworks-notifications

Discord/Slack webhook integration for stream-visible alerts.

```hcl
module "sunkworks_notifications" {
  source = "./modules/sunkworks-notifications"
  
  discord_webhook_url = var.discord_webhook
  slack_webhook_url   = var.slack_webhook
}
```

### sunkworks-backup

Cross-account backup with S3 replication and AWS Backup.

```hcl
module "sunkworks_backup" {
  source = "./modules/sunkworks-backup"
  
  backup_retention_days    = 30
  enable_cross_region_copy = true
  source_account_ids       = ["123456789012"]
}
```

### sunkworks-credential-rotation

Automatic credential rotation on exposure detection.

```hcl
module "sunkworks_credential_rotation" {
  source = "./modules/sunkworks-credential-rotation"
  
  sns_topic_arn            = module.notifications.sns_topic_arn
  enable_guardduty_trigger = true
}
```

## Legacy Modules

These modules pre-date the Sunkworks architecture but remain compatible:

- `bootstrap-admin` - Break-glass IAM user management
- `oidc-identity` - GitHub/GitLab OIDC providers
- `assumable-roles` - Role-based access control
- `bastion-ci` - Bastion host for CI/CD
- `vpc` - Basic VPC networking

## Scripts

Enhanced MFA scripts in `/scripts/`:

| Script | Purpose |
|--------|---------|
| `sunkworks-mfa.sh` | YubiKey TOTP and session management |
| `sunkworks-sso.sh` | AWS SSO with device trust |
| `sunkworks-planb.sh` | Fallback authentication methods |

## Tagging Requirements

All Sunkworks-managed resources should include:

```hcl
tags = {
  SunkworksManaged = "true"
  Episode          = "EP042-PIHOLE"  # Episode identifier
}
```

Protected resources add:

```hcl
tags = {
  NetworkProtected     = "true"  # VPC, subnets, route tables
  TerminationProtected = "true"  # EC2 instances
  Essential            = "true"  # Excluded from panic button
}
```
