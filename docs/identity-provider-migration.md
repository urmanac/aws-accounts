# Alternative Identity Provider Migration Guide

This document outlines migration strategies for transitioning between different OIDC identity providers, ensuring vendor independence and flexibility in your AWS authentication strategy.

## Overview

Our identity architecture supports three provider types:
1. **GitHub OIDC** (Primary implementation)
2. **GitLab OIDC** (Alternative 1)
3. **Custom OIDC** (Alternative 2 - Keycloak, Auth0, etc.)

Each provider can be enabled independently, allowing for gradual migration or parallel operation.

## Migration Scenarios

### Scenario 1: GitHub → GitLab Migration

#### Business Drivers
- Cost optimization (GitLab pricing model)
- Feature requirements (GitLab-specific CI/CD features)
- Vendor diversification strategy
- Self-hosting requirements

#### Migration Steps

##### Phase 1: Parallel Setup (No Disruption)
```hcl
# Enable both providers in Terraform
module "oidc_identity" {
  source = "./modules/oidc-identity"
  
  environment = var.environment
  
  # Enable both GitHub and GitLab
  enable_github_oidc = true
  enable_gitlab_oidc = true
  
  github_organizations = ["urmanac", "kingdon-ci"]
  gitlab_projects      = ["urmanac/aws-accounts", "kingdon-ci/infrastructure"]
}
```

##### Phase 2: GitLab Integration Testing
```yaml
# .gitlab-ci.yml example
variables:
  AWS_DEFAULT_REGION: us-east-1

assume_role:
  stage: setup
  image: amazon/aws-cli:latest
  id_tokens:
    GITLAB_OIDC_TOKEN:
      aud: sts.amazonaws.com
  script:
    - >
      STS_TOKEN=$(aws sts assume-role-with-web-identity
      --role-arn arn:aws:iam::$AWS_ACCOUNT_ID:role/$ENVIRONMENT-CI
      --role-session-name gitlab-ci-$CI_JOB_ID
      --web-identity-token $GITLAB_OIDC_TOKEN
      --duration-seconds 3600
      --query 'Credentials.[AccessKeyId,SecretAccessKey,SessionToken]'
      --output text)
    - export AWS_ACCESS_KEY_ID=$(echo $STS_TOKEN | cut -d' ' -f1)
    - export AWS_SECRET_ACCESS_KEY=$(echo $STS_TOKEN | cut -d' ' -f2)  
    - export AWS_SESSION_TOKEN=$(echo $STS_TOKEN | cut -d' ' -f3)
    - aws sts get-caller-identity
```

##### Phase 3: Repository Migration
```bash
#!/bin/bash
# Script: migrate-github-to-gitlab.sh

set -euo pipefail

GITHUB_ORG="urmanac"
GITLAB_GROUP="urmanac"
REPO_NAME="aws-accounts"

echo "🔄 Migrating ${GITHUB_ORG}/${REPO_NAME} to GitLab..."

# 1. Create GitLab project
gitlab-cli project create \
  --group ${GITLAB_GROUP} \
  --name ${REPO_NAME} \
  --description "AWS account management (migrated from GitHub)"

# 2. Mirror repository
git clone --mirror https://github.com/${GITHUB_ORG}/${REPO_NAME}.git
cd ${REPO_NAME}.git
git remote add gitlab https://gitlab.com/${GITLAB_GROUP}/${REPO_NAME}.git
git push --mirror gitlab

# 3. Update OIDC trust policies
aws iam update-assume-role-policy \
  --role-name sb-CI \
  --policy-document file://trust-policies/gitlab-only.json

echo "✅ Migration complete"
```

##### Phase 4: GitHub Deprecation
```hcl
# Disable GitHub OIDC provider
module "oidc_identity" {
  source = "./modules/oidc-identity"
  
  environment = var.environment
  
  # Disable GitHub, keep only GitLab
  enable_github_oidc = false
  enable_gitlab_oidc = true
  
  gitlab_projects = ["urmanac/aws-accounts", "kingdon-ci/infrastructure"]
}
```

#### Migration Checklist
- [ ] GitLab organization/group setup
- [ ] Repository migration with full history
- [ ] CI/CD pipeline conversion (GitHub Actions → GitLab CI)
- [ ] Secret/variable migration
- [ ] Team access and permissions mapping
- [ ] Documentation updates
- [ ] OIDC trust policy updates
- [ ] Monitoring and alerting migration
- [ ] Rollback plan preparation

### Scenario 2: GitHub → Self-Hosted (Keycloak) Migration

#### Business Drivers
- Complete vendor independence
- Enterprise compliance requirements
- Custom authentication workflows
- Data sovereignty requirements

#### Implementation Steps

##### Phase 1: Keycloak Setup
```bash
# Docker Compose setup for Keycloak
version: '3.8'
services:
  keycloak:
    image: quay.io/keycloak/keycloak:latest
    environment:
      KEYCLOAK_ADMIN: admin
      KEYCLOAK_ADMIN_PASSWORD: admin123
    ports:
      - "8080:8080"
    command: start-dev
    
  postgres:
    image: postgres:14
    environment:
      POSTGRES_DB: keycloak
      POSTGRES_USER: keycloak
      POSTGRES_PASSWORD: password
```

##### Phase 2: OIDC Configuration
```hcl
# Terraform configuration for Keycloak OIDC
module "oidc_identity" {
  source = "./modules/oidc-identity"
  
  environment = var.environment
  
  enable_github_oidc = true   # Keep during transition
  enable_custom_oidc = true   # Add Keycloak
  
  custom_oidc_url         = "https://auth.yourdomain.com"
  custom_oidc_thumbprints = ["a1b2c3d4e5f6..."]  # SSL certificate thumbprint
  custom_oidc_conditions = [
    {
      test     = "StringEquals"
      variable = "auth.yourdomain.com:aud"
      values   = ["sts.amazonaws.com"]
    },
    {
      test     = "StringLike" 
      variable = "auth.yourdomain.com:sub"
      values   = ["user:*"]
    }
  ]
}
```

##### Phase 3: User Migration Script
```python
#!/usr/bin/env python3
# Script: migrate-github-users-to-keycloak.py

import requests
import json
from keycloak import KeycloakAdmin

# GitHub API to get organization members
def get_github_members(org, token):
    headers = {"Authorization": f"token {token}"}
    response = requests.get(f"https://api.github.com/orgs/{org}/members", headers=headers)
    return response.json()

# Keycloak admin client
keycloak_admin = KeycloakAdmin(
    server_url="https://auth.yourdomain.com/",
    username="admin",
    password="admin123",
    realm_name="master"
)

# Create AWS realm
keycloak_admin.create_realm(
    payload={
        "realm": "aws",
        "enabled": True,
        "displayName": "AWS Authentication"
    }
)

# Get GitHub members and create in Keycloak
github_members = get_github_members("urmanac", "ghp_your_token")
for member in github_members:
    user_data = {
        "username": member["login"],
        "email": f"{member['login']}@yourdomain.com",
        "enabled": True,
        "emailVerified": True
    }
    keycloak_admin.create_user(payload=user_data, exist_ok=True)
    print(f"Created user: {member['login']}")
```

##### Phase 4: Authentication Flow Testing
```bash
#!/bin/bash
# Test Keycloak OIDC authentication

# Get token from Keycloak
KEYCLOAK_TOKEN=$(curl -s -X POST \
  "https://auth.yourdomain.com/realms/aws/protocol/openid-connect/token" \
  -H "Content-Type: application/x-www-form-urlencoded" \
  -d "grant_type=password" \
  -d "client_id=aws-client" \
  -d "username=testuser" \
  -d "password=testpass" | jq -r .access_token)

# Use token to assume AWS role
aws sts assume-role-with-web-identity \
  --role-arn arn:aws:iam::123456789012:role/sb-ReadOnly \
  --role-session-name keycloak-test \
  --web-identity-token $KEYCLOAK_TOKEN
```

#### Migration Checklist
- [ ] Keycloak infrastructure setup
- [ ] SSL certificate configuration
- [ ] Realm and client configuration
- [ ] User migration and testing
- [ ] Group/role mapping
- [ ] OIDC trust policy updates
- [ ] Backup authentication methods
- [ ] Operational procedures (backups, monitoring)
- [ ] Disaster recovery planning

### Scenario 3: Multi-Provider Strategy

#### Use Case
Maintain multiple identity providers for different purposes:
- **GitHub**: Development and CI/CD
- **GitLab**: Enterprise projects
- **Keycloak**: Internal corporate users

#### Configuration
```hcl
module "oidc_identity" {
  source = "./modules/oidc-identity"
  
  environment = var.environment
  
  # Enable all providers
  enable_github_oidc = true
  enable_gitlab_oidc = true  
  enable_custom_oidc = true
  
  # GitHub for development
  github_organizations = ["urmanac", "kingdon-ci"]
  
  # GitLab for enterprise
  gitlab_projects = ["enterprise/secure-project"]
  
  # Keycloak for corporate users
  custom_oidc_url = "https://auth.yourdomain.com"
  custom_oidc_conditions = [
    {
      test     = "StringEquals"
      variable = "auth.yourdomain.com:department"
      values   = ["engineering", "devops"]
    }
  ]
}
```

## Migration Tools and Scripts

### Universal Token Exchange Script
```bash
#!/bin/bash
# Script: universal-aws-auth.sh
# Supports multiple OIDC providers

PROVIDER="${1:-github}"  # github, gitlab, keycloak
ROLE_NAME="${2:-ReadOnly}"
ENVIRONMENT="${3:-sb}"

case $PROVIDER in
  "github")
    TOKEN=$(gh auth token)
    ;;
  "gitlab")
    TOKEN=$GITLAB_TOKEN  # From environment
    ;;
  "keycloak")
    TOKEN=$(get-keycloak-token.sh)  # Custom script
    ;;
  *)
    echo "Unknown provider: $PROVIDER"
    exit 1
    ;;
esac

# Universal role assumption
aws sts assume-role-with-web-identity \
  --role-arn "arn:aws:iam::$ACCOUNT_ID:role/$ENVIRONMENT-$ROLE_NAME" \
  --role-session-name "$PROVIDER-$ROLE_NAME-session" \
  --web-identity-token "$TOKEN"
```

### Provider Health Check
```bash
#!/bin/bash
# Script: check-oidc-providers.sh
# Validates all configured OIDC providers

ENVIRONMENT="${1:-sb}"

echo "🔍 Checking OIDC Provider Health..."

# Check GitHub
if gh auth status &>/dev/null; then
  echo "✅ GitHub: Authenticated"
  if TOKEN=$(gh auth token) && [ -n "$TOKEN" ]; then
    echo "✅ GitHub: Token available"
  else
    echo "❌ GitHub: Token unavailable"
  fi
else
  echo "❌ GitHub: Not authenticated"
fi

# Check GitLab  
if [ -n "${GITLAB_TOKEN:-}" ]; then
  echo "✅ GitLab: Token configured"
  if curl -s -H "Authorization: Bearer $GITLAB_TOKEN" \
     "https://gitlab.com/api/v4/user" &>/dev/null; then
    echo "✅ GitLab: Token valid"
  else
    echo "❌ GitLab: Token invalid"
  fi
else
  echo "❌ GitLab: Token not configured"
fi

# Check custom OIDC (Keycloak)
if [ -n "${KEYCLOAK_URL:-}" ]; then
  if curl -s "$KEYCLOAK_URL/.well-known/openid_configuration" &>/dev/null; then
    echo "✅ Keycloak: Endpoint accessible"
  else
    echo "❌ Keycloak: Endpoint inaccessible"
  fi
else
  echo "❌ Keycloak: URL not configured"
fi
```

## Rollback Procedures

### Emergency Rollback to IAM Users
```bash
#!/bin/bash
# Script: emergency-rollback-to-iam.sh
# Quickly restore IAM user access if OIDC fails

echo "🚨 Emergency Rollback to IAM Users"

# Re-enable AdministratorAccess for break-glass group
aws iam attach-group-policy \
  --group-name "break-glass-admins-sb" \
  --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

echo "✅ Emergency access restored"
echo "⚠️  Don't forget to disable after emergency resolved"
```

### Provider Failover
```bash
#!/bin/bash
# Script: failover-provider.sh
# Switch between OIDC providers quickly

OLD_PROVIDER="${1}"  # github, gitlab, keycloak
NEW_PROVIDER="${2}"  # github, gitlab, keycloak

echo "🔄 Failing over from $OLD_PROVIDER to $NEW_PROVIDER"

# Update trust policies to prioritize new provider
# Implementation depends on your automation setup
terraform apply -var="primary_oidc_provider=$NEW_PROVIDER"
```

## Best Practices for Vendor Independence

### 1. Configuration as Code
- All identity configurations in Terraform
- Version controlled trust policies
- Automated deployment pipelines

### 2. Regular Testing
- Monthly failover tests
- Automated provider health checks
- Break-glass access validation

### 3. Documentation Maintenance
- Keep migration procedures updated
- Document provider-specific quirks
- Maintain troubleshooting guides

### 4. Monitoring and Alerting
- Provider availability monitoring
- Authentication failure alerts
- Unusual access pattern detection

### 5. Cost Management
- Track provider-specific costs
- Monitor token usage patterns
- Optimize session durations

## Future Considerations

### Additional Providers
- **Azure Active Directory**: Enterprise integration
- **Google Cloud Identity**: Multi-cloud scenarios
- **Okta/Auth0**: Managed identity services

### Advanced Features
- **Conditional Access**: Time/location-based restrictions
- **Step-up Authentication**: MFA for sensitive operations
- **Just-in-Time Access**: Temporary role elevation

### Automation Opportunities
- **Automated Failover**: Health-check driven provider switching
- **Policy Synchronization**: Multi-provider policy consistency
- **User Lifecycle Management**: Automated provisioning/deprovisioning

This migration guide ensures you maintain flexibility and vendor independence while providing clear paths for transitioning between identity providers as your requirements evolve.