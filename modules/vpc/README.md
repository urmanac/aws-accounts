# VPC Module

This module creates AWS VPC infrastructure with IPv6 support, designed for hosting ephemeral bastion instances and supporting modern cloud-native workloads.

## Purpose

This module provides the networking foundation for:

1. **Bastion host deployment** with both IPv4 and IPv6 connectivity
2. **SSM-based management** via VPC endpoints for private communication
3. **Scalable subnet architecture** supporting both public and private workloads
4. **Security group management** for different service types

## Architecture

```
VPC (IPv4 + IPv6)
├── Internet Gateway (IPv4 + IPv6)
├── Public Subnets (2 AZs)
│   ├── Bastion instances
│   ├── Public load balancers
│   └── NAT gateways (future)
├── Private Subnets (2 AZs) 
│   ├── Application workloads
│   ├── Databases
│   └── Internal services
├── VPC Endpoints
│   ├── S3 Gateway Endpoint
│   └── SSM Interface Endpoints (optional)
└── Security Groups
    ├── Bastion security group
    ├── SSM endpoint security group
    └── Application security groups (future)
```

## What This Module Creates

### Core Networking
- **VPC** with IPv4 CIDR and auto-assigned IPv6 CIDR block
- **Internet Gateway** for public internet access
- **Public subnets** (2 AZs) with public IP assignment
- **Private subnets** (2 AZs) for internal workloads
- **Route tables** with appropriate IPv4/IPv6 routing

### VPC Endpoints
- **S3 Gateway Endpoint**: Cost-effective S3 access for SSM agent updates
- **SSM Interface Endpoints** (optional): Private connectivity for Systems Manager

### Security Groups
- **Bastion Security Group**: SSH access from anywhere (when enabled)
- **Endpoint Security Group**: HTTPS access for VPC endpoints
- Designed for expansion with application-specific security groups

## Key Features

### IPv6 Support
- Full dual-stack IPv4/IPv6 configuration
- Automatic IPv6 CIDR allocation from AWS
- IPv6 routing through Internet Gateway
- Bastion instances get both IPv4 and IPv6 addresses

### Conditional Features
- **Bastion networking** can be enabled/disabled via variables
- **Private networking** (SSM VPC endpoints) optional for cost control
- Designed for free-tier compatibility when endpoints are disabled

### Security Considerations
- Public subnets only for resources that need internet access
- Private subnets for sensitive workloads
- Security groups with principle of least privilege
- VPC endpoints reduce internet traffic for AWS services

## Usage

### Basic VPC (No Bastion)
```hcl
module "vpc" {
  source = "./modules/vpc"
  
  name   = "sandbox-us"
  cidr   = "10.20.0.0/16"
  region = "us-east-1"
}
```

### VPC with Bastion Support
```hcl
module "vpc_eu_west_1" {
  source = "./modules/vpc"
  
  name   = "sandbox-eu"
  cidr   = "10.10.0.0/16" 
  region = "eu-west-1"
  
  # Enable bastion networking components
  enable_bastion_networking = true
  
  # Optional: Enable private SSM endpoints (costs money)
  enable_bastion_private_networking = false
}
```

### Integration with Bastion Module
```hcl
module "bastion_ci" {
  source = "./modules/bastion-ci"
  
  # Use VPC outputs
  vpc_id                    = module.vpc_eu_west_1.vpc_id
  public_subnet_ids         = module.vpc_eu_west_1.public_subnet_ids
  private_subnet_ids        = module.vpc_eu_west_1.private_subnet_ids
  ssm_security_group_id     = module.vpc_eu_west_1.ssm_security_group_id
  bastion_security_group_id = module.vpc_eu_west_1.bastion_security_group_id
}
```

## Cost Optimization

### Free Tier Compatibility
- VPC, subnets, route tables, Internet Gateway: **Free**
- S3 Gateway Endpoint: **Free**
- Security groups: **Free**

### Optional Paid Components
- **SSM Interface Endpoints**: ~$22/month per endpoint (3 endpoints = ~$66/month)
- **NAT Gateway**: ~$45/month + data processing charges
- Enable only when needed for private subnet internet access

### Cost-Conscious Design
```hcl
# Minimal cost configuration
enable_bastion_networking         = true   # Free security groups
enable_bastion_private_networking = false  # Skip paid VPC endpoints

# Full private connectivity (costs money)
enable_bastion_networking         = true
enable_bastion_private_networking = true   # Enables SSM VPC endpoints
```

## Variables

| Variable | Type | Default | Description |
|----------|------|---------|-------------|
| `name` | string | - | Name prefix for VPC resources |
| `cidr` | string | - | IPv4 CIDR block for VPC |
| `region` | string | - | AWS region for deployment |
| `enable_bastion_networking` | bool | `false` | Enable bastion security group |
| `enable_bastion_private_networking` | bool | `false` | Enable SSM VPC endpoints |

## Outputs

| Output | Description |
|--------|-------------|
| `vpc_id` | ID of the created VPC |
| `public_subnet_ids` | List of public subnet IDs |
| `private_subnet_ids` | List of private subnet IDs |
| `ssm_security_group_id` | Security group ID for SSM endpoints |
| `bastion_security_group_id` | Security group ID for bastion hosts |

## Security Features

### Network Segmentation
- Clear separation between public and private subnets
- Private subnets have no direct internet access
- Application workloads isolated from public internet

### Security Group Design
- Bastion SG allows SSH from anywhere (ephemeral use case)
- Endpoint SG restricts HTTPS to VPC CIDR only
- Extensible design for application-specific security groups

### IPv6 Security
- IPv6 addresses are public by default (AWS design)
- Security groups provide same protection for IPv6 as IPv4
- Consider IPv6-specific security group rules for applications

## Design Principles

### Ephemeral Infrastructure
- Designed for tear-down and rebuild scenarios
- No persistent networking dependencies
- Bastion instances are temporary (scheduled start/stop)

### Scalability
- 2 AZ design provides high availability foundation
- Subnet sizing allows for future expansion
- Security group structure supports application growth

### Cost Consciousness
- Optional features to control costs
- Gateway endpoints preferred over interface endpoints
- Free-tier compatible in basic configuration

## Future Enhancements

- **NAT Gateway support** for private subnet internet access
- **VPC Flow Logs** integration for network monitoring
- **Application Load Balancer** subnets and security groups
- **Database subnet groups** for RDS deployment
- **VPC Peering** support for multi-VPC architectures