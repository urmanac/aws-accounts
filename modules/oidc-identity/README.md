# OIDC Identity Providers Module

This module manages OIDC (OpenID Connect) identity providers for AWS IAM federation, supporting multiple identity providers with a focus on vendor independence.

## Supported Identity Providers

### 1. GitHub (Primary Implementation)
- **Provider URL**: `https://token.actions.githubusercontent.com`
- **Use Cases**: GitHub Actions CI/CD, personal authentication via GitHub CLI
- **Organizations**: `urmanac`, `kingdon-ci`
- **Trust Conditions**: Repository-based access control

### 2. GitLab (Alternative 1 - Future Implementation)
- **Provider URL**: `https://gitlab.com`
- **Use Cases**: GitLab CI/CD, migration path from GitHub
- **Projects**: Configurable project-based access
- **Trust Conditions**: Project path-based access control

### 3. Custom OIDC (Alternative 2 - Future Implementation)
- **Provider URL**: Configurable (e.g., Keycloak, Auth0)
- **Use Cases**: Self-hosted identity, enterprise integration
- **Configuration**: Fully customizable trust conditions
- **Trust Conditions**: Flexible condition-based access control

## Architecture

```
AWS IAM Roles
├── Trust Relationship → GitHub OIDC Provider
├── Trust Relationship → GitLab OIDC Provider (future)
└── Trust Relationship → Custom OIDC Provider (future)

Each provider supports:
├── Organization/Project-based access control
├── Audience validation
└── Custom trust conditions
```

## Usage

### Basic GitHub-only Setup
```hcl
module "oidc_identity" {
  source      = "./modules/oidc-identity"
  environment = var.environment
  
  # GitHub only (default)
  enable_github_oidc   = true
  github_organizations = ["urmanac", "kingdon-ci"]
}
```

### Multi-Provider Setup
```hcl
module "oidc_identity" {
  source      = "./modules/oidc-identity"
  environment = var.environment
  
  # Enable multiple providers
  enable_github_oidc = true
  enable_gitlab_oidc = true
  enable_custom_oidc = true
  
  # GitHub configuration
  github_organizations = ["urmanac", "kingdon-ci"]
  
  # GitLab configuration
  gitlab_projects = ["group/project1", "group/project2"]
  
  # Custom OIDC configuration (e.g., Keycloak)
  custom_oidc_url         = "https://auth.yourdomain.com"
  custom_oidc_thumbprints = ["abc123..."]
  custom_oidc_conditions = [
    {
      test     = "StringEquals"
      variable = "auth.yourdomain.com:sub"
      values   = ["user:admin"]
    }
  ]
}
```

## Trust Policy Integration

The module outputs trust policy documents that can be used with IAM roles:

```hcl
resource "aws_iam_role" "example_role" {
  name               = "ExampleRole"
  assume_role_policy = module.oidc_identity.multi_provider_trust_policy
}
```

## Migration Strategy

### Phase 1: GitHub Implementation (Current)
- Implement GitHub OIDC provider
- Test with GitHub Actions and personal authentication
- Maintain IAM users as backup

### Phase 2: GitLab Alternative (Future)
- Add GitLab OIDC provider
- Test migration scenarios
- Document GitLab-specific workflows

### Phase 3: Self-hosted Alternative (Future)
- Implement Keycloak or similar
- Complete vendor independence
- Document operational requirements

## Security Considerations

- **Audience Validation**: All providers validate `sts.amazonaws.com` audience
- **Repository/Project Restrictions**: Access limited to specified repos/projects
- **Thumbprint Validation**: SSL certificate thumbprints verified
- **Condition-based Access**: Fine-grained trust policy conditions

## Vendor Independence

This module is designed for easy migration between identity providers:

1. **Provider-agnostic Role Design**: IAM roles trust multiple providers
2. **Configuration-driven**: Provider selection via variables
3. **Documented Migration Paths**: Clear procedures for provider switching
4. **Backup Access**: IAM users maintained for emergency access

## Future Enhancements

- Support for additional OIDC providers (Azure AD, Google, etc.)
- Dynamic provider registration
- Advanced trust policy templating
- Integration with AWS IAM Identity Center