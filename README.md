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

## IAM Role-Based Access Control (RBAC) Architecture

### Current State
We currently grant permissions directly to IAM users via group memberships. While this works, it violates the principle of least privilege and doesn't provide proper audit trails for different types of access.

### Proposed Improvement: Assumable Roles for Human Users

We should implement a role-based access control system where:

1. **IAM users have minimal base permissions** (just enough to assume roles)
2. **All real permissions are granted via assumable roles**
3. **Each role represents a specific job function or security context**
4. **Role assumptions are logged in CloudTrail for audit purposes**
5. **AWS Extend Switch Roles (AESR) browser extension** provides easy context switching

### Proposed Role Structure

#### 1. `ReadOnly` Role
- **Purpose**: Investigation, monitoring, compliance checking
- **Permissions**: Read-only access across all AWS services
- **Use Cases**: 
  - Troubleshooting issues
  - Cost analysis and optimization research
  - Security posture review
  - General exploration and learning

#### 2. `Billing` Role  
- **Purpose**: Financial management and cost control
- **Permissions**: 
  - Full access to Cost Explorer, Budgets, Billing
  - Read access to resource inventory for cost attribution
- **Use Cases**:
  - Monthly cost reviews
  - Budget setup and monitoring
  - Cost optimization analysis
  - Invoice and payment management

#### 3. `Security` Role
- **Purpose**: Security administration and compliance
- **Permissions**:
  - IAM management (users, roles, policies)
  - CloudTrail, Config, GuardDuty administration
  - Security hub and findings management
- **Use Cases**:
  - User access management
  - Security configuration changes
  - Compliance monitoring and reporting
  - Incident response and investigation

#### 4. `Developer` Role
- **Purpose**: Application deployment and management (not infrastructure)
- **Permissions**:
  - EC2 instance management (but not VPC/networking changes)
  - Lambda function deployment
  - RDS database management
  - S3 bucket operations for application data
  - Application-specific resource management
- **Use Cases**:
  - Deploying applications
  - Managing application data
  - Application troubleshooting
  - Performance tuning

#### 5. `Admin` Role
- **Purpose**: Full administrative access (emergency use only)
- **Permissions**: AdministratorAccess (current level)
- **Use Cases**:
  - Emergency infrastructure changes
  - Complex cross-service operations
  - Account-level configuration changes
  - Should be used sparingly with justification

#### 6. `CI` Role (Enhanced)
- **Purpose**: Infrastructure-as-code operations
- **Permissions**: Infrastructure management via Terraform/OpenTofu
- **Use Cases**:
  - Terraform apply operations
  - Infrastructure provisioning and changes
  - CI/CD pipeline operations
  - Automated deployments

### Implementation Plan

#### Phase 1: Role Creation
1. Create the assumable roles with appropriate policies
2. Configure trust relationships to allow assumption by IAM users
3. Add MFA requirement for role assumption
4. Test role assumption manually

#### Phase 2: User Permission Migration  
1. Remove direct AdministratorAccess from user groups
2. Grant users only the permissions needed to:
   - Assume roles (with MFA)
   - Change their own passwords
   - Manage their own MFA devices
3. Update scripts and documentation

#### Phase 3: AESR Configuration
1. Generate AESR configuration file
2. Document browser extension setup
3. Provide role assumption examples for different contexts

#### Phase 4: Audit and Monitoring
1. Set up CloudTrail log analysis for role assumptions
2. Create dashboards for role usage patterns
3. Regular access reviews and role refinement

### Benefits of This Approach

1. **Principle of Least Privilege**: Users only get permissions they need for specific tasks
2. **Audit Trail**: Every privileged action is clearly attributed to a specific role/context
3. **Temporal Scoping**: Role sessions expire, limiting blast radius of compromised credentials
4. **Clear Intent**: Role names make it obvious what type of work is being performed
5. **AESR Integration**: Easy context switching without complex credential management
6. **Future-Proof**: Scales to organization-level identity management (IAM Identity Center)

### Security Considerations

- All role assumptions require MFA
- Role sessions are time-limited (1-12 hours based on role type)
- CloudTrail logs provide complete audit trail
- No standing privileges - all access is explicitly assumed
- Follows AWS security best practices for human user access

--Product of various AI assistants and human refinement
