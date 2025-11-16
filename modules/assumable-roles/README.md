# Assumable Roles Module

This module creates a comprehensive set of assumable IAM roles designed for role-based access control (RBAC) with OIDC federation support.

## Role Architecture

### 1. ReadOnly Role
- **Purpose**: Investigation, monitoring, compliance checking
- **Permissions**: AWS ReadOnlyAccess managed policy
- **Session Duration**: 4 hours
- **Use Cases**:
  - Troubleshooting and investigation
  - Cost analysis and optimization research
  - Security posture review
  - Learning and exploration

### 2. Billing Role
- **Purpose**: Financial management and cost control
- **Permissions**: Billing managed policy + extended cost management
- **Session Duration**: 2 hours
- **Use Cases**:
  - Monthly cost reviews
  - Budget setup and monitoring
  - Cost optimization analysis
  - Invoice and payment management

### 3. Security Role
- **Purpose**: Security administration and compliance
- **Permissions**: IAM, CloudTrail, Config, GuardDuty, Security Hub
- **Session Duration**: 1 hour (sensitive operations)
- **Use Cases**:
  - User access management
  - Security configuration changes
  - Compliance monitoring and reporting
  - Incident response and investigation

### 4. Developer Role
- **Purpose**: Application deployment and management
- **Permissions**: Application-focused services (EC2 instances, Lambda, RDS, S3)
- **Session Duration**: 8 hours (full workday)
- **Restrictions**: Cannot modify VPC/networking or IAM
- **Use Cases**:
  - Deploying applications
  - Managing application data
  - Application troubleshooting
  - Performance tuning

### 5. Admin Role
- **Purpose**: Full administrative access (emergency use only)
- **Permissions**: AdministratorAccess
- **Session Duration**: 1 hour (time-limited for security)
- **Use Cases**:
  - Emergency infrastructure changes
  - Complex cross-service operations
  - Account-level configuration changes

### 6. CI Role
- **Purpose**: Infrastructure-as-code operations
- **Permissions**: Full access with regional restrictions
- **Session Duration**: 12 hours (for long-running deployments)
- **Use Cases**:
  - Terraform/OpenTofu apply operations
  - Infrastructure provisioning and changes
  - CI/CD pipeline operations
  - Automated deployments

## Security Features

### Session Duration Limits
Each role has an appropriate maximum session duration based on its purpose:
- **ReadOnly**: 4 hours (investigation work)
- **Billing**: 2 hours (monthly reviews)
- **Security**: 1 hour (sensitive operations)
- **Developer**: 8 hours (full workday)
- **Admin**: 1 hour (emergency only)
- **CI**: 12 hours (long deployments)

### Regional Restrictions
The CI role includes regional restrictions to prevent accidental resource creation in unexpected regions.

### Principle of Least Privilege
- Developer role cannot modify networking or IAM
- Billing role focuses only on cost management
- Security role has elevated privileges but short session duration

### Break-Glass Access
A special policy allows emergency IAM user access to assume roles with MFA requirement.

## Usage

### Basic Setup
```hcl
module "assumable_roles" {
  source = "./modules/assumable-roles"
  
  environment       = var.environment
  role_prefix      = "${var.environment}-"
  oidc_trust_policy = module.oidc_identity.multi_provider_trust_policy
  
  allowed_regions = ["us-east-1", "eu-west-1"]
}
```

### Custom Session Durations
```hcl
module "assumable_roles" {
  source = "./modules/assumable-roles"
  
  environment       = var.environment
  oidc_trust_policy = module.oidc_identity.multi_provider_trust_policy
  
  # Custom session durations
  developer_session_duration = 14400  # 4 hours
  admin_session_duration     = 1800   # 30 minutes
}
```

## Integration with OIDC

These roles are designed to work with OIDC providers (GitHub, GitLab, Keycloak):

```bash
# Assume role via GitHub OIDC
gh auth token | aws sts assume-role-with-web-identity \
  --role-arn arn:aws:iam::ACCOUNT:role/ReadOnly \
  --role-session-name github-session \
  --web-identity-token file:///dev/stdin

# Assume role via local tooling
aws-oidc-assume ReadOnly
```

## AWS Extend Switch Roles (AESR) Integration

The module outputs AESR configuration data for easy browser-based role switching:

```json
{
  "roles": [
    {
      "role_arn": "arn:aws:iam::ACCOUNT:role/ReadOnly",
      "display_name": "ReadOnly",
      "color": "4CAF50"
    }
  ]
}
```

## Emergency Access

In case OIDC providers are unavailable, IAM users can assume roles using the break-glass policy:

```bash
aws sts assume-role \
  --role-arn arn:aws:iam::ACCOUNT:role/Admin \
  --role-session-name emergency-access
```

**Requirements**: MFA must be present in the session.

## Best Practices

1. **Use appropriate roles**: Don't use Admin for routine tasks
2. **Short sessions for sensitive roles**: Security and Admin roles have 1-hour limits
3. **Regional awareness**: CI role restricts regions to prevent accidental deployment
4. **Regular access review**: Monitor CloudTrail for role assumption patterns
5. **Break-glass testing**: Regularly test emergency IAM user access

## Monitoring and Auditing

All role assumptions are logged in CloudTrail with the following information:
- Source identity (OIDC provider and user)
- Role assumed
- Session duration
- Actions performed during session

## Future Enhancements

- Dynamic policy attachment based on environment
- Time-based access restrictions (business hours only)
- Integration with AWS Config for compliance monitoring
- Automated role usage analysis and optimization