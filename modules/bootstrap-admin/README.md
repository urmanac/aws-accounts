# Bootstrap Admin Module

This module manages the initial administrative access setup for AWS accounts, focusing on break-glass emergency access in an OIDC-federated environment.

## Purpose

In our modern OIDC-based architecture, this module provides:

1. **Break-glass IAM users** for emergency access when OIDC providers are unavailable
2. **Minimal base permissions** required for role assumption
3. **MFA enforcement** for all administrative operations
4. **Transition support** from legacy direct-permission model to OIDC federation

## Architecture

```
Break-glass IAM Users
├── terraform-admin (imported legacy user)
├── terraform-admin-{environment} (environment-specific user)
└── break-glass-admins-{environment} group
    ├── Minimal base permissions (password, MFA, role assumption)
    ├── MFA enforcement policy
    └── Optional role assumption policy (from assumable-roles module)
```

## What This Module Creates

### IAM Users
- **`terraform-admin`**: Imported legacy user, repurposed for break-glass access
- **`terraform-admin-{environment}`**: Environment-specific break-glass user

### IAM Group  
- **`break-glass-admins-{environment}`**: Group with minimal permissions for emergency access

### Policies
- **`BreakGlassBasePermissions`**: Allows password change, MFA management, basic STS operations
- **`RequireMFA`**: Enforces MFA for most AWS operations
- **`CostExplorerAccess`**: Billing and cost analysis permissions (legacy)

## Key Security Features

### Minimal Permissions
Break-glass users can only:
- Change their own passwords
- Manage their own MFA devices  
- Get session tokens with MFA
- Assume roles (if break-glass policy is attached)

### MFA Enforcement
The MFA policy denies most AWS operations unless:
- MFA is present in the session, OR
- The action is explicitly allowed (password change, MFA management)

### Role Assumption Integration
When integrated with the `assumable-roles` module, break-glass users can assume OIDC roles with MFA, providing a fallback when OIDC providers are unavailable.

## Usage

### Basic Setup
```hcl
module "bootstrap_admin" {
  source      = "./modules/bootstrap-admin"
  environment = "sb"
  account_id  = "123456789012"
}
```

### Integrated with Assumable Roles
```hcl
module "bootstrap_admin" {
  source      = "./modules/bootstrap-admin"
  environment = "sb"
  account_id  = "123456789012"
  
  # Connect to assumable roles for break-glass access
  break_glass_assume_roles_policy_arn = module.assumable_roles.break_glass_policy_arn
}
```

## Emergency Access Procedures

### When OIDC is Unavailable
1. Use break-glass IAM user credentials
2. Authenticate with MFA: `aws sts get-session-token --serial-number ... --token-code ...`
3. Assume appropriate role: `aws sts assume-role --role-arn ... --role-session-name emergency`
4. Perform necessary operations
5. Document incident and restore OIDC access

### Break-glass Testing
Regular testing ensures emergency procedures work:
```bash
# Test break-glass access monthly
aws sts get-session-token \
  --serial-number arn:aws:iam::ACCOUNT:mfa/terraform-admin \
  --token-code 123456

aws sts assume-role \
  --role-arn arn:aws:iam::ACCOUNT:role/sb-Admin \
  --role-session-name break-glass-test
```

## Migration Context

### Legacy State (Pre-OIDC)
- Direct `AdministratorAccess` policy attachment
- Users performed all operations with permanent privileges
- No temporal scoping or role-based context

### Current State (OIDC Transition)
- Minimal break-glass permissions only
- OIDC roles provide actual working permissions
- Clear separation between emergency and normal access

### Future State (Full OIDC)
- Break-glass users maintained but rarely used
- All normal operations via OIDC federation
- Clear audit trail for any break-glass usage

## Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `environment` | string | - | Environment name (sb, prod) |
| `account_id` | string | - | AWS Account ID |
| `admin_username` | string | `terraform-admin` | Username for break-glass accounts |
| `break_glass_assume_roles_policy_arn` | string | `null` | ARN of policy allowing role assumption |

## Outputs

| Output | Description |
|--------|-------------|
| `admin_username` | Name of the break-glass admin user |
| `admin_policy_arn` | ARN of the MFA requirement policy |
| `break_glass_group_name` | Name of the break-glass administrators group |
| `break_glass_base_policy_arn` | ARN of the break-glass base permissions policy |

## Security Considerations

1. **MFA Required**: All operations require MFA authentication
2. **Minimal Permissions**: Users cannot perform AWS operations without role assumption
3. **Audit Trail**: All break-glass usage is logged in CloudTrail
4. **Regular Testing**: Emergency procedures should be tested monthly
5. **Temporary Use**: Break-glass access should be documented and time-limited

## Relationship to Other Modules

- **`assumable-roles`**: Provides roles that break-glass users can assume
- **`oidc-identity`**: Primary authentication method (break-glass is fallback)
- **Legacy integration**: Imports existing `terraform-admin` user for continuity