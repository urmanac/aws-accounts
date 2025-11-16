# Terraform Modules Overview

This directory contains a collection of Terraform modules designed to implement a modern, secure, and vendor-independent AWS identity and infrastructure architecture.

## Module Collection Goals

The modules in this directory work together to provide:

1. **OIDC-based Identity Federation** - Keyless authentication with multiple provider support
2. **Role-based Access Control** - Granular permissions with temporal scoping  
3. **Break-glass Emergency Access** - Reliable fallback when modern systems fail
4. **Ephemeral Infrastructure** - Cost-effective, scalable, destroyable resources
5. **Vendor Independence** - No lock-in to any single identity provider or cloud pattern

## Module Architecture

```
┌─────────────────────────────────────────────────────────────┐
│                    Identity & Access Layer                  │
├─────────────────────┬───────────────────┬───────────────────┤
│   oidc-identity     │  assumable-roles  │  bootstrap-admin  │
│                     │                   │                   │
│ • GitHub OIDC       │ • ReadOnly Role   │ • Break-glass     │
│ • GitLab OIDC       │ • Billing Role    │   IAM Users       │
│ • Custom OIDC       │ • Security Role   │ • MFA Enforcement │
│ • Trust Policies    │ • Developer Role  │ • Emergency Access│
│                     │ • Admin Role      │                   │
│                     │ • CI Role         │                   │
└─────────────────────┴───────────────────┴───────────────────┘
┌─────────────────────────────────────────────────────────────┐
│                   Infrastructure Layer                      │
├─────────────────────────────┬───────────────────────────────┤
│           vpc               │         bastion-ci            │
│                             │                               │
│ • IPv4/IPv6 Networking      │ • Ephemeral Compute           │
│ • Public/Private Subnets    │ • Scheduled Start/Stop        │
│ • VPC Endpoints             │ • SSM Management              │
│ • Security Groups           │ • CI/CD Role Integration      │
│ • Internet Gateway          │ • Infrastructure Automation   │
└─────────────────────────────┴───────────────────────────────┘
```

## Module Descriptions

### Identity & Access Modules

#### [`oidc-identity/`](oidc-identity/README.md)
**Purpose**: Multi-provider OIDC federation setup
- Creates GitHub, GitLab, and custom OIDC providers
- Generates trust policies for role assumption
- Supports vendor independence and migration strategies
- Configures repository/project-based access control

#### [`assumable-roles/`](assumable-roles/README.md) 
**Purpose**: Role-based access control with temporal scoping
- Six specialized roles for different job functions
- Time-limited sessions (1-12 hours based on role)
- Principle of least privilege enforcement
- Integration with OIDC trust policies

#### [`bootstrap-admin/`](bootstrap-admin/README.md)
**Purpose**: Break-glass emergency access and legacy transition
- Minimal IAM users for emergency scenarios  
- MFA enforcement and basic permissions
- Bridge between legacy and modern authentication
- Role assumption capabilities for emergencies

### Infrastructure Modules

#### [`vpc/`](vpc/README.md)
**Purpose**: Modern networking foundation with IPv6 support
- Dual-stack IPv4/IPv6 VPC configuration
- Public/private subnet architecture
- Cost-optimized VPC endpoint strategy
- Security group management

#### [`bastion-ci/`](bastion-ci/README.md)
**Purpose**: Ephemeral infrastructure automation platform
- Scheduled start/stop for cost optimization
- SSM-based management (no SSH keys in production)
- CI/CD role integration for infrastructure automation
- Wireguard VPN and development tools

## Integration Patterns

### Complete Identity Setup
```hcl
# Multi-provider identity federation
module "oidc_identity" {
  source = "./modules/oidc-identity"
  # ... configuration
}

# Role-based access control
module "assumable_roles" {
  source = "./modules/assumable-roles"
  oidc_trust_policy = module.oidc_identity.multi_provider_trust_policy
  # ... configuration
}

# Emergency access fallback
module "bootstrap_admin" {
  source = "./modules/bootstrap-admin"
  break_glass_assume_roles_policy_arn = module.assumable_roles.break_glass_policy_arn
  # ... configuration
}
```

### Complete Infrastructure Setup
```hcl
# Networking foundation
module "vpc" {
  source = "./modules/vpc"
  enable_bastion_networking = true
  # ... configuration
}

# Ephemeral compute platform
module "bastion_ci" {
  source = "./modules/bastion-ci"
  vpc_id                    = module.vpc.vpc_id
  public_subnet_ids         = module.vpc.public_subnet_ids
  ssm_security_group_id     = module.vpc.ssm_security_group_id
  bastion_security_group_id = module.vpc.bastion_security_group_id
  # ... configuration
}
```

## Design Principles

### 1. Vendor Independence
- **Multiple OIDC providers**: GitHub, GitLab, Keycloak support
- **Provider abstraction**: Same roles work with any provider
- **Migration paths**: Clear procedures for switching providers
- **No lock-in**: Can replace AWS, GitHub, or any other vendor

### 2. Security by Design
- **Zero standing privileges**: All access via role assumption
- **MFA everywhere**: Required for all privileged operations
- **Temporal scoping**: Time-limited sessions prevent credential misuse
- **Audit trails**: Complete CloudTrail logging of all actions

### 3. Cost Optimization  
- **Ephemeral resources**: Infrastructure scales to zero when not needed
- **Free-tier friendly**: Optional paid features clearly marked
- **Regional restrictions**: Prevent accidental expensive deployments
- **Resource lifecycle**: Automated start/stop scheduling

### 4. Operational Excellence
- **Infrastructure as Code**: Everything defined in Terraform
- **Immutable infrastructure**: Tear down and rebuild rather than patch
- **Clear documentation**: Each module self-documents its purpose
- **Testing procedures**: Built-in validation and rollback plans

## Module Dependencies

```
oidc-identity (standalone)
     ↓
assumable-roles (requires: oidc-identity)
     ↓  
bootstrap-admin (optional: assumable-roles)

vpc (standalone)
     ↓
bastion-ci (requires: vpc)
```

## Getting Started

1. **Start with identity**: Deploy `oidc-identity` and `assumable-roles`
2. **Test authentication**: Use scripts to assume roles via GitHub OIDC
3. **Add infrastructure**: Deploy `vpc` and `bastion-ci` for compute needs
4. **Configure break-glass**: Set up `bootstrap-admin` for emergency access
5. **Migrate workflows**: Replace IAM user access with OIDC role assumption

## Module Maturity

| Module | Status | Completeness | Production Ready |
|--------|--------|--------------|------------------|
| `oidc-identity` | ✅ Stable | 100% | Yes |
| `assumable-roles` | ✅ Stable | 100% | Yes |
| `bootstrap-admin` | ✅ Stable | 100% | Yes |
| `vpc` | ✅ Stable | 100% | Yes |
| `bastion-ci` | ✅ Stable | 100% | Yes |

All modules are production-ready and include comprehensive documentation, security controls, and operational procedures.