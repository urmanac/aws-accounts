# GitHub OIDC Integration Guide

This guide covers setting up and using GitHub OIDC authentication with AWS IAM roles for secure, keyless access to AWS resources.

## Overview

GitHub OIDC allows you to authenticate to AWS without storing long-lived AWS credentials. Instead, GitHub provides short-lived tokens that can be exchanged for AWS credentials through IAM role assumption.

## GitHub Organizations Setup

### Current Configuration
- **Primary Org**: `urmanac` - Your main organization
- **Secondary Org**: `kingdon-ci` - CI/CD focused organization  
- **Kaniko-builder dependency**: This project migrating from GitLab to GitHub aligns with our OIDC strategy

### Repository Access Patterns

#### Personal Repositories
```yaml
# In GitHub Actions workflow
permissions:
  id-token: write   # Required for OIDC
  contents: read    # Standard repository access

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Configure AWS credentials
        uses: aws-actions/configure-aws-credentials@v3
        with:
          role-to-assume: arn:aws:iam::${{ secrets.AWS_ACCOUNT_ID }}:role/${{ vars.ENVIRONMENT }}-ReadOnly
          role-session-name: github-${{ github.actor }}-${{ github.run_id }}
          aws-region: us-east-1
```

#### Organization Repositories  
```yaml
# Workflow in urmanac/* or kingdon-ci/* repositories
- name: Assume AWS Role
  uses: aws-actions/configure-aws-credentials@v3
  with:
    role-to-assume: arn:aws:iam::ACCOUNT:role/sb-CI
    role-session-name: ${{ github.repository }}-${{ github.run_id }}
    aws-region: eu-west-1
```

## Local Development Setup

### Prerequisites
```bash
# Install GitHub CLI
brew install gh

# Install AWS CLI v2
curl "https://awscli.amazonaws.com/AWSCLIV2.pkg" -o "AWSCLIV2.pkg"
sudo installer -pkg AWSCLIV2.pkg -target /

# Install jq for JSON parsing
brew install jq
```

### Authentication Scripts

#### GitHub Token to AWS Credentials
```bash
#!/bin/bash
# File: scripts/gh-aws-auth.sh
set -euo pipefail

ROLE_ARN="${1}"
SESSION_NAME="${2:-github-cli-session}"

# Get GitHub token
GH_TOKEN=$(gh auth token)

# Exchange for AWS credentials
CREDENTIALS=$(aws sts assume-role-with-web-identity \
  --role-arn "${ROLE_ARN}" \
  --role-session-name "${SESSION_NAME}" \
  --web-identity-token "${GH_TOKEN}" \
  --duration-seconds 3600)

# Export credentials
export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r .Credentials.AccessKeyId)
export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r .Credentials.SecretAccessKey) 
export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r .Credentials.SessionToken)

echo "✓ AWS credentials configured for role: ${ROLE_ARN}"
echo "✓ Session expires in 1 hour"
```

#### Role Assumption Helper
```bash
#!/bin/bash
# File: scripts/aws-assume-role.sh
set -euo pipefail

ROLE_NAME="${1}"
ENVIRONMENT="${2:-sb}"
ACCOUNT_ID="${3:-$(aws sts get-caller-identity --query Account --output text)}"

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ENVIRONMENT}-${ROLE_NAME}"

echo "Assuming role: ${ROLE_ARN}"
source ./scripts/gh-aws-auth.sh "${ROLE_ARN}" "local-${ROLE_NAME}-session"
```

### Usage Examples

#### Read-Only Access
```bash
# Assume ReadOnly role for investigation
./scripts/aws-assume-role.sh ReadOnly sb

# Now you can run read-only AWS commands
aws ec2 describe-instances
aws s3 ls
aws iam list-roles
```

#### Billing Analysis
```bash
# Assume Billing role for cost analysis
./scripts/aws-assume-role.sh Billing prod

# Analyze costs
aws ce get-cost-and-usage --time-period Start=2024-10-01,End=2024-10-31 --granularity MONTHLY --metrics BlendedCost
```

#### Infrastructure Changes
```bash
# Assume CI role for Terraform operations
./scripts/aws-assume-role.sh CI sb

# Run Terraform
tofu plan -var-file=sb.tfvars -state=sb.tfstate
tofu apply -var-file=sb.tfvars -state=sb.tfstate
```

#### Emergency Admin Access
```bash
# Assume Admin role for emergency changes
./scripts/aws-assume-role.sh Admin prod

# Perform emergency operations (session limited to 1 hour)
aws iam create-role --role-name EmergencyRole --assume-role-policy-document file://policy.json
```

## GitHub Actions Integration

### Repository Variables Setup
Set these in each repository's Settings > Secrets and variables > Actions:

#### Variables
```
ENVIRONMENT=sb              # or prod
AWS_ACCOUNT_ID=123456789012 # Your account ID
AWS_DEFAULT_REGION=us-east-1
```

#### Repository Secrets (if needed)
```
# Generally not needed with OIDC, but might be useful for:
SLACK_WEBHOOK_URL=https://hooks.slack.com/...
NOTIFICATION_EMAIL=alerts@yourdomain.com
```

### Workflow Templates

#### Infrastructure Deployment
```yaml
# .github/workflows/infrastructure.yml
name: Infrastructure Deployment

on:
  push:
    branches: [main]
    paths: ['terraform/**']
  pull_request:
    paths: ['terraform/**']

permissions:
  id-token: write
  contents: read

jobs:
  plan:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup OpenTofu
        uses: opentofu/setup-opentofu@v1
        
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v3
        with:
          role-to-assume: arn:aws:iam::${{ vars.AWS_ACCOUNT_ID }}:role/${{ vars.ENVIRONMENT }}-CI
          role-session-name: github-ci-${{ github.run_id }}
          aws-region: ${{ vars.AWS_DEFAULT_REGION }}
          
      - name: Terraform Plan
        run: |
          tofu init
          tofu plan -var-file=${{ vars.ENVIRONMENT }}.tfvars -state=${{ vars.ENVIRONMENT }}.tfstate
          
  apply:
    needs: plan
    if: github.ref == 'refs/heads/main'
    runs-on: ubuntu-latest
    environment: ${{ vars.ENVIRONMENT }}  # Require approval for apply
    steps:
      - uses: actions/checkout@v4
      
      - name: Setup OpenTofu
        uses: opentofu/setup-opentofu@v1
        
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v3
        with:
          role-to-assume: arn:aws:iam::${{ vars.AWS_ACCOUNT_ID }}:role/${{ vars.ENVIRONMENT }}-CI
          role-session-name: github-ci-apply-${{ github.run_id }}
          aws-region: ${{ vars.AWS_DEFAULT_REGION }}
          
      - name: Terraform Apply
        run: |
          tofu init
          tofu apply -auto-approve -var-file=${{ vars.ENVIRONMENT }}.tfvars -state=${{ vars.ENVIRONMENT }}.tfstate
```

#### Application Deployment
```yaml
# .github/workflows/deploy-app.yml
name: Deploy Application

on:
  push:
    branches: [main]
    paths: ['src/**']

permissions:
  id-token: write
  contents: read

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      
      - name: Configure AWS Credentials
        uses: aws-actions/configure-aws-credentials@v3
        with:
          role-to-assume: arn:aws:iam::${{ vars.AWS_ACCOUNT_ID }}:role/${{ vars.ENVIRONMENT }}-Developer
          role-session-name: github-deploy-${{ github.run_id }}
          aws-region: ${{ vars.AWS_DEFAULT_REGION }}
          
      - name: Deploy to Lambda
        run: |
          aws lambda update-function-code \
            --function-name my-app-function \
            --zip-file fileb://app.zip
```

## Token Scoping and Security

### Repository-level Access Control
```hcl
# Trust policy conditions in Terraform
condition {
  test     = "StringLike"
  variable = "token.actions.githubusercontent.com:sub"
  values   = [
    "repo:urmanac/aws-accounts:*",
    "repo:urmanac/kaniko-builder:*",
    "repo:kingdon-ci/*:*"
  ]
}
```

### Branch Protection
```hcl
# Restrict to specific branches
condition {
  test     = "StringEquals"
  variable = "token.actions.githubusercontent.com:ref"
  values   = ["refs/heads/main", "refs/heads/develop"]
}
```

### Environment-specific Roles
```hcl
# Production requires specific repo and environment
condition {
  test     = "StringEquals"
  variable = "token.actions.githubusercontent.com:environment"
  values   = ["production"]
}
```

## Troubleshooting

### Common Issues

#### "AssumeRoleWithWebIdentity is not authorized"
- Check trust policy allows your repository
- Verify GitHub organization is in allowed list
- Ensure `id-token: write` permission is set

#### "Token audience is invalid"
- Confirm `aud` claim is `sts.amazonaws.com`
- Check OIDC provider client ID list

#### "Token subject is invalid"
- Verify repository name matches trust policy
- Check branch/environment restrictions

### Debug Commands
```bash
# Decode GitHub token (locally)
gh auth token | base64 -d | jq .

# Check current AWS identity
aws sts get-caller-identity

# List assumable roles
aws iam list-roles --query 'Roles[?contains(RoleName, `OIDC`) || contains(RoleName, `GitHub`)].RoleName'
```

## Migration from IAM Users

### Phase 1: Parallel Operation
1. Keep existing IAM user workflows
2. Add OIDC authentication to new workflows
3. Test thoroughly in sandbox environment

### Phase 2: Gradual Migration
1. Update repository workflows one by one
2. Monitor CloudTrail for authentication patterns
3. Document any issues or gaps

### Phase 3: IAM User Deprecation
1. Remove AWS keys from GitHub Secrets
2. Restrict IAM users to break-glass access only
3. Update documentation and training

## Integration with Kaniko-builder

The kaniko-builder project's migration from GitLab to GitHub aligns perfectly with this OIDC strategy:

### Before (GitLab)
```yaml
# GitLab CI configuration
variables:
  AWS_ACCESS_KEY_ID: $AWS_ACCESS_KEY_ID      # Stored in GitLab secrets
  AWS_SECRET_ACCESS_KEY: $AWS_SECRET_ACCESS_KEY
```

### After (GitHub OIDC)
```yaml
# GitHub Actions configuration  
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v3
  with:
    role-to-assume: arn:aws:iam::${{ vars.AWS_ACCOUNT_ID }}:role/sb-CI
    role-session-name: kaniko-builder-${{ github.run_id }}
```

This eliminates stored secrets and provides better audit trails for the kaniko-builder project's AWS operations.

## Security Best Practices

1. **Minimal Trust Policies**: Only allow necessary repositories
2. **Short Session Durations**: Default to 1 hour, extend only when needed
3. **Regular Access Reviews**: Monitor CloudTrail for unusual patterns
4. **Branch Protection**: Restrict production access to protected branches
5. **Environment Gates**: Use GitHub Environments for production approvals
6. **Token Monitoring**: Watch for token usage anomalies
7. **Break-glass Testing**: Regularly verify IAM user backup access works