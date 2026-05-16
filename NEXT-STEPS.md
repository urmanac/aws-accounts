# 🚀 NEXT STEPS - Implementation Guide

**⚠️ IMPORTANT**: This document contains the step-by-step implementation plan for deploying the new OIDC-based identity architecture. Follow these steps in order after reviewing all documentation.

## Prerequisites Checklist

Before proceeding, ensure you have:

- [ ] **GitHub CLI installed and authenticated**: `gh auth login`
- [ ] **AWS CLI v2 installed**: Version 2.x required for OIDC
- [ ] **OpenTofu/Terraform installed**: Current version
- [ ] **jq installed**: For JSON processing in scripts
- [ ] **1Password CLI** (if continuing to use MFA): `op` command
- [ ] **Current AWS access**: Via existing IAM user method
- [ ] **Account IDs documented**: In `.env.sb` and `.env.prod` files

## Phase 1: Deploy OIDC Infrastructure

### Step 1.1: Create Environment Files
```bash
# Create .env.sb (replace with your actual account ID)
echo "ACCOUNT_ID=YOUR_SANDBOX_ACCOUNT_ID" > .env.sb

# Create .env.prod (replace with your actual account ID)  
echo "ACCOUNT_ID=YOUR_PROD_ACCOUNT_ID" > .env.prod

# Verify no account numbers in git-tracked files
git status --porcelain | grep -E "\.(tf|md|sh)$" | xargs grep -l "ACCOUNT_ID=" || echo "✅ No account IDs in tracked files"
```

### Step 1.2: Deploy to Sandbox First
```bash
# Authenticate with existing method
export AWS_PROFILE=sb-bootstrap
source ./get_mfa_session.sh
aws_mfa

# Plan the deployment
tofu plan -var-file=sb.tfvars -state=sb.tfstate

# Review the plan carefully - should show:
# + OIDC providers (GitHub, GitLab disabled, Custom disabled)  
# + 6 new IAM roles (ReadOnly, Billing, Security, Developer, Admin, CI)
# + Updated IAM user permissions (reduced to break-glass only)
# ~ Modified existing resources (minimal changes)

# Deploy when ready
tofu apply -var-file=sb.tfvars -state=sb.tfstate
```

### Step 1.3: Verify Deployment
```bash
# Check OIDC providers were created
aws iam list-open-id-connect-providers

# Check roles were created
aws iam list-roles --query 'Roles[?contains(RoleName, `sb-`)].RoleName'

# Verify GitHub OIDC provider thumbprint
aws iam get-open-id-connect-provider --open-id-connect-provider-arn $(aws iam list-open-id-connect-providers --query 'OpenIDConnectProviderList[?contains(Arn, `github`)].Arn' --output text)
```

## Phase 2: Test GitHub OIDC Authentication

### Step 2.1: Make Scripts Executable
```bash
chmod +x scripts/*.sh
```

### Step 2.2: Test Role Assumption
```bash
# Test ReadOnly role (safest to start with)
./scripts/aws-assume-role.sh ReadOnly sb

# If successful, you should see:
# ✓ AWS credentials configured successfully
# Account: YOUR_ACCOUNT_ID
# Role: arn:aws:iam::YOUR_ACCOUNT_ID:role/sb-ReadOnly

# Test AWS access with the assumed role
aws sts get-caller-identity
aws ec2 describe-regions  # Should work (read-only)
```

### Step 2.3: Test Different Roles
```bash
# Test each role type
./scripts/aws-assume-role.sh Billing sb     # Cost and billing access
./scripts/aws-assume-role.sh Developer sb   # Application deployment
./scripts/aws-assume-role.sh Security sb    # IAM and security management
./scripts/aws-assume-role.sh CI sb          # Infrastructure as code

# Test Admin role (be careful!)
./scripts/aws-assume-role.sh Admin sb       # Full access, 1-hour limit
```

### Step 2.4: Generate Browser Extension Config
```bash
# Generate AESR configuration for easy role switching
./scripts/generate-aesr-config.sh sb
./scripts/generate-aesr-config.sh prod

# Install browser extension and import the generated JSON files
# Chrome: https://chrome.google.com/webstore/detail/aws-extend-switch-roles/jpmkfafbacpgapdghgdpembnojdlgkdl
# Firefox: https://addons.mozilla.org/en-US/firefox/addon/aws-extend-switch-roles/
```

## Phase 3: Deploy to Production

### Step 3.1: Production Deployment
```bash
# Switch to production profile
export AWS_PROFILE=prod-bootstrap
source ./get_mfa_session.sh
aws_mfa

# Deploy to production
tofu plan -var-file=prod.tfvars -state=prod.tfstate
tofu apply -var-file=prod.tfvars -state=prod.tfstate

# Test production access
./scripts/aws-assume-role.sh ReadOnly prod
```

## Phase 4: Update Workflows and Scripts

### Step 4.1: Update GitHub Actions
For any repositories using AWS credentials, update workflows:

```yaml
# Old method (remove)
- name: Configure AWS credentials
  uses: aws-actions/configure-aws-credentials@v3
  with:
    aws-access-key-id: ${{ secrets.AWS_ACCESS_KEY_ID }}
    aws-secret-access-key: ${{ secrets.AWS_SECRET_ACCESS_KEY }}

# New method (replace with)  
- name: Configure AWS credentials via OIDC
  uses: aws-actions/configure-aws-credentials@v3
  with:
    role-to-assume: arn:aws:iam::${{ vars.AWS_ACCOUNT_ID }}:role/${{ vars.ENVIRONMENT }}-CI
    role-session-name: github-ci-${{ github.run_id }}
    aws-region: ${{ vars.AWS_DEFAULT_REGION }}

permissions:
  id-token: write  # Required for OIDC
  contents: read
```

### Step 4.2: Update Bastion Instance Schedule
The bastion instance currently starts at 7 AM and stops at 12 PM EST. Consider adjusting for afternoon work:

```hcl
# In modules/bastion-ci/main.tf, update scheduled actions:
resource "aws_autoscaling_schedule" "start" {
  recurrence = "0 17 * * *"  # 12 PM EST (17 UTC) - afternoon start
}

resource "aws_autoscaling_schedule" "stop" {
  recurrence = "0 22 * * *"  # 5 PM EST (22 UTC) - evening stop  
}
```

This timing works better for:
- **Mecris project**: Can run on bastion in afternoon/evening
- **Development workflow**: Aligns with typical coding hours
- **Cost optimization**: Still provides 5-hour daily window

### Step 4.3: Plan Mecris Integration
The bastion instance is perfect for hosting the **mecris** project:

- **Scheduled availability**: Automatic start/stop saves costs
- **Proper networking**: VPC with IPv6, Wireguard access
- **Development tools**: Git, OpenTofu, development environment
- **Secure access**: SSM Session Manager, no exposed SSH
- **CI/CD integration**: Can assume roles for AWS operations

## Phase 5: Clean Up Legacy Access

### Step 5.1: Remove AWS Keys from Repositories
```bash
# Check for stored AWS credentials in repositories
grep -r "AWS_ACCESS_KEY_ID" .github/ || echo "✅ No hardcoded keys found"
grep -r "AWS_SECRET_ACCESS_KEY" .github/ || echo "✅ No hardcoded secrets found"

# Remove AWS credentials from GitHub repository secrets
# Go to Settings > Secrets and variables > Actions
# Delete: AWS_ACCESS_KEY_ID, AWS_SECRET_ACCESS_KEY
```

### Step 5.2: Validate Break-glass Access
```bash
# Test emergency IAM user access (without OIDC)
unset AWS_ACCESS_KEY_ID AWS_SECRET_ACCESS_KEY AWS_SESSION_TOKEN

# Use traditional MFA method
source ./get_mfa_session.sh
aws_mfa

# Test role assumption via IAM user
aws sts assume-role \
  --role-arn "arn:aws:iam::ACCOUNT_ID:role/sb-Admin" \
  --role-session-name "break-glass-test"
```

## Phase 6: Enable Alternative Providers (Future)

### Step 6.1: GitLab OIDC (When Needed)
```hcl
# In main.tf, update oidc_identity module:
module "oidc_identity" {
  enable_gitlab_oidc = true
  gitlab_projects    = ["urmanac/aws-accounts", "urmanac/other-project"]
}
```

### Step 6.2: Custom OIDC/Keycloak (When Needed)
```hcl
# For complete vendor independence
module "oidc_identity" {
  enable_custom_oidc      = true
  custom_oidc_url         = "https://auth.yourdomain.com"
  custom_oidc_thumbprints = ["certificate-thumbprint"]
}
```

## Troubleshooting

### Common Issues

#### "AssumeRoleWithWebIdentity is not authorized"
- Check GitHub authentication: `gh auth status`
- Verify repository is in allowed organizations (`urmanac`, `kingdon-ci`)
- Ensure GitHub token has required claims

#### "No identity providers found"
- Verify OIDC provider deployment: `aws iam list-open-id-connect-providers`
- Check trust policy configuration in roles

#### "MFA required" errors
- For break-glass access, ensure MFA session: `aws sts get-session-token`
- For OIDC access, this error shouldn't occur

### Recovery Procedures

#### Emergency: Restore Full IAM User Access
```bash
# If OIDC completely fails, restore emergency access
aws iam attach-group-policy \
  --group-name "break-glass-admins-sb" \
  --policy-arn "arn:aws:iam::aws:policy/AdministratorAccess"

# Remember to remove after emergency is resolved!
```

#### Rollback to Previous Configuration
```bash
# If deployment fails, rollback
git checkout HEAD~1  # Go back to previous commit
tofu plan -var-file=sb.tfvars -state=sb.tfstate
tofu apply -var-file=sb.tfvars -state=sb.tfstate
```

## Success Criteria

✅ **Phase 1 Complete**: OIDC providers and roles deployed successfully  
✅ **Phase 2 Complete**: GitHub OIDC authentication working for all roles  
✅ **Phase 3 Complete**: Production environment deployed and tested  
✅ **Phase 4 Complete**: Workflows updated to use OIDC instead of keys  
✅ **Phase 5 Complete**: Legacy access methods removed, break-glass validated  

## Notes for Implementation

- **Account ID Security**: The `.env.*` files contain account IDs but are gitignored
- **Testing Order**: Always test in sandbox before production
- **Role Validation**: Test each role type to ensure proper permissions
- **Browser Integration**: AESR extension provides convenient role switching
- **Emergency Access**: Keep break-glass procedures documented and tested

## After Implementation

Once complete, you'll have:
- **Keyless authentication** via GitHub OIDC
- **Role-based access** with appropriate permissions and time limits
- **Vendor independence** with clear migration paths to GitLab or Keycloak
- **Cost-optimized infrastructure** with scheduled bastion instances
- **Modern security posture** following AWS best practices

The implementation aligns perfectly with the kaniko-builder migration from GitLab to GitHub and provides a foundation for the mecris project deployment on the bastion instance.