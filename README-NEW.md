# AWS Accounts - OIDC Identity Architecture

Modern AWS identity management with OIDC federation, role-based access control, and vendor independence.

## Quick Start

### Current Access Methods

**🔑 OIDC-based Access (Recommended)**
```bash
# Assume roles via GitHub OIDC
./scripts/aws-assume-role.sh ReadOnly sb
./scripts/aws-assume-role.sh Developer sb
./scripts/aws-assume-role.sh Admin prod

# Generate browser extension config
./scripts/generate-aesr-config.sh sb
```

**🚨 Legacy IAM Access (Transitional)**
```bash
export AWS_PROFILE=sb-bootstrap
source ./get_mfa_session.sh
aws_mfa
```

## Architecture

```
GitHub OIDC ──┐
GitLab OIDC ──┼──→ AWS IAM Roles ──→ AWS Resources
Keycloak ─────┘    (6 Role Types)
     │
     └─→ Break-glass IAM Users (Emergency)
```

### Available Roles
- **ReadOnly** (4h) - Investigation, monitoring
- **Billing** (2h) - Cost management  
- **Security** (1h) - IAM, security admin
- **Developer** (8h) - Application deployment
- **Admin** (1h) - Emergency full access
- **CI** (12h) - Infrastructure automation

## Project Structure

```
├── modules/                    # Terraform modules
│   ├── oidc-identity/         # Multi-provider OIDC setup
│   ├── assumable-roles/       # Role-based access control
│   ├── bootstrap-admin/       # Break-glass emergency access
│   ├── vpc/                   # Network infrastructure
│   └── bastion-ci/           # Ephemeral compute platform
├── scripts/                   # Authentication helpers
├── docs/                      # Detailed documentation
└── NEXT-STEPS.md             # Implementation guide
```

## Key Features

✅ **Vendor Independence** - GitHub, GitLab, Keycloak support  
✅ **Zero Standing Privileges** - All access via role assumption  
✅ **Time-Limited Sessions** - Role-appropriate duration limits  
✅ **Break-glass Access** - Emergency fallback when OIDC fails  
✅ **Cost Optimized** - Ephemeral infrastructure, free-tier friendly  
✅ **Audit Ready** - Complete CloudTrail logging  

## Documentation

- **[📋 Next Steps](NEXT-STEPS.md)** - Step-by-step implementation guide
- **[🏗️ Modules Overview](modules/README.md)** - Architecture and module descriptions
- **[🔗 GitHub OIDC Setup](docs/github-oidc-integration.md)** - Complete integration guide
- **[🔄 Provider Migration](docs/identity-provider-migration.md)** - Vendor independence strategies
- **[🏛️ Architecture Details](ARCHITECTURE.md)** - MFA and security design

## Related Projects

- **[kaniko-builder](https://github.com/urmanac/kaniko-builder)** - Migrating to GitHub OIDC
- **mecris** - Will be deployed on bastion instance

## Implementation Status

🚀 **Ready for deployment** - All modules implemented and documented

The configuration in this repository ensures AWS access keys are secured with MFA enforcement, provides modern OIDC-based authentication, and maintains vendor independence with clear migration paths.

---
*Built with security, cost optimization, and vendor independence in mind.*