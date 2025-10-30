This repo has been sanitized by BFG

## Quick Start

### Legacy IAM User Access (Transitional)
```bash
export AWS_PROFILE=sb-bootstrap
export AWS_PROFILE=prod-bootstrap

source ./get_mfa_session.sh
aws_mfa
```

### Modern OIDC-based Access (Recommended)
```bash
# Assume roles via GitHub OIDC
./scripts/aws-assume-role.sh ReadOnly sb
./scripts/aws-assume-role.sh Developer sb
./scripts/aws-assume-role.sh Admin prod

# Generate AESR browser extension config
./scripts/generate-aesr-config.sh sb
./scripts/generate-aesr-config.sh prod
```

## Architecture Overview

### Current State: Hybrid IAM + OIDC
We are in transition from direct IAM user access to OIDC-based role assumption:

```
┌─────────────────┐    ┌──────────────────┐    ┌─────────────────┐
│   GitHub OIDC   │────│   AWS IAM Roles  │────│  AWS Resources  │
│  (Primary IdP)  │    │  (6 Role Types)  │    │   (EC2, S3,...)  │
└─────────────────┘    └──────────────────┘    └─────────────────┘
        │                       │
        │              ┌─────────────────┐
        │              │  Break-glass    │
        └──────────────│   IAM Users     │
                       │ (Emergency Only)│
                       └─────────────────┘
```

### Target State: Multi-Provider OIDC
```
┌─────────────────┐
│   GitHub OIDC   │────┐
│   (Primary)     │    │
└─────────────────┘    │    ┌──────────────────┐    ┌─────────────────┐
                       ├────│   AWS IAM Roles  │────│  AWS Resources  │
┌─────────────────┐    │    │  (6 Role Types)  │    │                 │
│   GitLab OIDC   │────┤    └──────────────────┘    └─────────────────┘
│ (Alternative 1) │    │
└─────────────────┘    │
                       │
┌─────────────────┐    │
│  Keycloak OIDC  │────┘
│ (Alternative 2) │
└─────────────────┘
```

You must have AWS Credentials in a file in ~/.aws/credentials, or export them
in environment variables.

The configuration in this Terraform module ensures that AWS Access Keys are
limited when they have not yet MFA'ed. And we can have Test and Prod.

## OIDC-Based Identity Architecture

### Implemented Solution
We have implemented a modern, vendor-independent identity architecture based on OIDC (OpenID Connect) federation with AWS IAM roles.

#### Key Components

**1. OIDC Identity Providers** (`modules/oidc-identity/`)
- **GitHub OIDC** (Primary): Integrated with `urmanac` and `kingdon-ci` organizations
- **GitLab OIDC** (Alternative 1): Ready for future implementation
- **Custom OIDC** (Alternative 2): Supports Keycloak, Auth0, or any OIDC provider

**2. Assumable Roles** (`modules/assumable-roles/`)
- **ReadOnly** (4h sessions): Investigation, monitoring, compliance
- **Billing** (2h sessions): Cost management and financial analysis  
- **Security** (1h sessions): IAM management, security administration
- **Developer** (8h sessions): Application deployment, no infrastructure changes
- **Admin** (1h sessions): Full access for emergencies only
- **CI** (12h sessions): Infrastructure-as-code operations

**3. Break-glass IAM Users** (`modules/bootstrap-admin/`)
- Minimal permissions (password change, MFA management, role assumption)
- Emergency access when OIDC providers are unavailable
- MFA-protected role assumption capability

### Vendor Independence Strategy

#### Multi-Provider Support
Our architecture supports multiple OIDC providers simultaneously:
- **No single point of failure**: If GitHub is down, use GitLab or Keycloak
- **Easy migration**: Switch providers without changing role structure
- **Provider-specific use cases**: Different providers for different teams/purposes

#### Migration Paths
- **GitHub → GitLab**: For cost optimization or feature requirements
- **GitHub → Keycloak**: For complete vendor independence
- **Multi-provider**: Parallel operation for redundancy

### Integration with Existing Projects

#### Kaniko-builder Dependency
The kaniko-builder project's migration from GitLab to GitHub aligns perfectly with our OIDC strategy:
- **Before**: Stored AWS credentials in GitLab secrets
- **After**: Keyless authentication via GitHub OIDC
- **Benefits**: Better security, audit trails, no credential rotation

#### Current GitHub Organizations
- **`urmanac`**: Primary organization for personal/main projects
- **`kingdon-ci`**: CI/CD focused organization
- **Repository Access**: Scoped to specific repositories within organizations

### Security Features

#### Principle of Least Privilege
- Users have no direct AWS permissions
- All access via time-limited role assumption
- Role-specific permission boundaries
- MFA required for sensitive operations

#### Audit and Compliance
- Complete CloudTrail logging of all role assumptions
- Clear attribution: OIDC token → User identity → AWS actions
- Session-based access with defined expiration
- No long-lived credentials in repositories

#### Regional and Temporal Controls
- CI role restricted to specific AWS regions
- Session duration limits based on role sensitivity
- Time-based access patterns (business hours enforcement possible)

### Implementation Status

#### ✅ Completed
- [x] OIDC identity provider module with multi-provider support
- [x] Six assumable roles with appropriate permissions and session limits
- [x] Break-glass IAM user transition (removed direct AdministratorAccess)
- [x] GitHub OIDC integration with urmanac/kingdon-ci organizations
- [x] Local authentication scripts for role assumption
- [x] AESR browser extension configuration generator
- [x] Comprehensive documentation for all migration scenarios

#### 🔄 Next Steps
1. **Deploy the new modules**: Run `terraform apply` to create OIDC providers and roles
2. **Test GitHub OIDC**: Verify authentication with personal GitHub account
3. **Migrate workflows**: Update CI/CD pipelines to use OIDC instead of IAM keys
4. **Enable alternative providers**: Configure GitLab/Keycloak as needed
5. **Deprecate IAM user access**: Remove direct permissions after OIDC validation

### Quick Reference

#### Essential Commands
```bash
# Assume different roles for different tasks
./scripts/aws-assume-role.sh ReadOnly sb      # Investigation
./scripts/aws-assume-role.sh Billing prod     # Cost analysis  
./scripts/aws-assume-role.sh Developer sb     # App deployment
./scripts/aws-assume-role.sh CI sb             # Infrastructure changes
./scripts/aws-assume-role.sh Admin prod       # Emergency only

# Generate browser extension config
./scripts/generate-aesr-config.sh sb
./scripts/generate-aesr-config.sh prod
```

#### Environment Files
```bash
# .env.sb
ACCOUNT_ID=123456789012

# .env.prod  
ACCOUNT_ID=987654321098
```

#### GitHub Actions Integration
```yaml
- name: Configure AWS Credentials
  uses: aws-actions/configure-aws-credentials@v3
  with:
    role-to-assume: arn:aws:iam::${{ vars.AWS_ACCOUNT_ID }}:role/${{ vars.ENVIRONMENT }}-CI
    role-session-name: github-ci-${{ github.run_id }}
```

### Documentation
- **[GitHub OIDC Integration](docs/github-oidc-integration.md)**: Complete setup guide
- **[Identity Provider Migration](docs/identity-provider-migration.md)**: Vendor independence strategies
- **[Module Documentation](modules/*/README.md)**: Technical implementation details

--Product of various AI assistants and human refinement
