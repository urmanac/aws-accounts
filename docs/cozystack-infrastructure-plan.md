# CozyStack Infrastructure Deployment Plan

**Date**: 2025-11-23  
**Target**: AWS Sandbox Environment (eu-west-1)  
**Goal**: Deploy CozyStack demo infrastructure for CozySummit Virtual 2025

## Overview

This plan bridges the `aws-accounts` Terraform infrastructure with the `cozystack-moon-and-back` project requirements. We'll create cost-optimized, easily teardown-able infrastructure that supports the boot-to-talos workflow.

## Repository Coordination

### aws-accounts (This Repo)
- **Purpose**: Terraform/OpenTofu infrastructure as code
- **State**: Local tfstate files (sb.tfstate for sandbox)
- **Deploy Method**: `make apply-sb` / `make plan-sb`
- **Authentication**: MFA via `source get_mfa_session.sh && aws_mfa && save_mfa`

### cozystack-moon-and-back
- **Purpose**: Custom Talos images, cluster config, documentation
- **Build Method**: GitHub Actions → GHCR
- **Access**: Filesystem MCP (`/Users/yebyen/u/c/cozystack-moon-and-back`)

## Critical Design Requirements

### Cost Management & Teardown
All per-hour cost infrastructure MUST be in dedicated modules for easy destruction:

```
modules/
├── cozy-demo/           # ALL demo infrastructure goes here
│   ├── main.tf         # Module entry point
│   ├── bastion.tf      # Bastion host with ENI
│   ├── talos-nodes.tf  # EC2 instances for Talos
│   ├── registry.tf     # ECR repos (if used)
│   ├── variables.tf
│   └── outputs.tf
└── (existing modules remain untouched)
```

**Teardown command**: 
```bash
# Emergency stop - kills all running instances
make nuke-costs
```

### Thread 1: Bastion Services Updates

**Current State** (from aws-accounts DESKTOP.md):
- Bastion already exists with ENI at 10.10.0.100
- Has SSH access via IPv6
- Has Wire guard tunnel to university

**Required Updates**:
1. **Registry Pull-Through Cache**
   - Deploy `registry:2` container with GHCR proxy
   - Ports 5050-5054 for different registries
   - Alternative: Use ECR pull-through cache (easier to tear down)
   
2. **Tailscale Integration**
   - Bastion becomes Tailscale subnet router
   - Advertises 10.10.0.0/24 subnet
   - Provides access to Talos nodes without public IPs

**Implementation**: Update existing bastion module user-data

### Thread 2: Talos Node Infrastructure

**Goal**: 3 EC2 instances (1 gateway, 2 compute) that boot-to-talos

#### Node Configuration
```
talos-gateway-1: 10.10.0.101 (t4g.medium)
  - Image: ghcr.io/urmanac/cozystack-moon-and-back/talos-arm64-gateway:latest
  - Extensions: spin, tailscale, drbd, zfs
  
talos-compute-2: 10.10.0.102 (t4g.medium)
  - Image: ghcr.io/urmanac/cozystack-moon-and-back/talos-arm64-compute:latest
  - Extensions: spin, drbd, zfs

talos-compute-3: 10.10.0.103 (t4g.medium)
  - Same as compute-2
```

#### Security Group Requirements
```hcl
# New security group: cozy-demo-talos-nodes
Ingress:
- Bastion (10.10.0.100) → Registry caches (5050-5054/tcp)
- Bastion (10.10.0.100) → Talos API (50000-50001/tcp)
- Bastion (10.10.0.100) → Kubernetes API (6443/tcp)
- Bastion (10.10.0.100) → Tailscale (41641/udp)
- Self → All traffic (inter-node K8s communication)

Egress:
- All traffic (needs to pull images)
```

#### boot-to-talos User-Data Template
```bash
#!/bin/bash
set -euxo pipefail
exec > >(tee /var/log/boot-to-talos.log) 2>&1

# Install boot-to-talos
BOOT_VERSION="v0.3.0"
curl -LO "https://github.com/cozystack/boot-to-talos/releases/download/${BOOT_VERSION}/boot-to-talos-linux-arm64.tar.gz"
tar -xzf boot-to-talos-linux-arm64.tar.gz
chmod +x boot-to-talos
mv boot-to-talos /usr/local/bin/

# Configure static networking
KERNEL_ARGS="ip=${node_ip}::10.10.0.1:255.255.255.0:${node_name}:eth0:off::"

# Run installation
echo "${talos_image}" > /tmp/boot-config
echo "/dev/xvda" >> /tmp/boot-config
echo "${KERNEL_ARGS}" >> /tmp/boot-config

boot-to-talos --non-interactive --config /tmp/boot-config
```

## Phase 1: Terraform Infrastructure

### Step 1.1: Create Cost-Managed Module

**File**: `modules/cozy-demo/main.tf`
```hcl
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

# All demo resources with Demo tag for tracking
locals {
  common_tags = {
    Demo    = "cozystack-moon-and-back"
    Project = "CozySummit2025"
    ManagedBy = "terraform"
  }
}
```

### Step 1.2: Bastion ENI (if not exists)

Check if ENI already exists, create if needed:
```hcl
resource "aws_network_interface" "bastion_eni" {
  subnet_id         = var.subnet_id
  private_ips       = ["10.10.0.100"]
  security_groups   = var.bastion_security_groups
  source_dest_check = false  # Enable IP forwarding

  tags = merge(local.common_tags, {
    Name = "cozy-demo-bastion-eni"
  })
}
```

### Step 1.3: Registry Option A - ECR Pull-Through Cache

**Pros**: Native AWS, easy billing, automatic teardown
**Cons**: Slightly more complex setup

```hcl
resource "aws_ecr_pull_through_cache_rule" "ghcr" {
  ecr_repository_prefix = "ghcr"
  upstream_registry_url = "ghcr.io"
}

# Bastion user-data references ECR endpoint
```

### Step 1.4: Registry Option B - Docker registry:2

**Pros**: Simple, works exactly like home lab
**Cons**: Manual container management

```bash
# In bastion user-data
docker run -d -p 5000:5000 \
  -e REGISTRY_PROXY_REMOTEURL=https://ghcr.io \
  --name ghcr-cache \
  registry:2
```

### Step 1.5: Talos Node Resources

**Launch Templates** (not instances - for easy manual launch):
```hcl
data "aws_ami" "amazon_linux_arm64" {
  most_recent = true
  owners      = ["amazon"]
  
  filter {
    name   = "name"
    values = ["al2023-ami-*-arm64"]
  }
}

resource "aws_launch_template" "talos_node" {
  for_each = var.talos_nodes
  
  name_prefix   = "cozy-talos-${each.value.name}-"
  image_id      = data.aws_ami.amazon_linux_arm64.id
  instance_type = "t4g.medium"
  
  user_data = base64encode(templatefile("${path.module}/templates/boot-to-talos.sh.tpl", {
    talos_image = "ghcr.io/urmanac/cozystack-moon-and-back/talos-arm64-${each.value.variant}:latest"
    node_ip     = each.value.private_ip
    node_name   = each.value.name
  }))
  
  network_interfaces {
    subnet_id       = var.subnet_id
    security_groups = [aws_security_group.talos_nodes.id]
  }
  
  tags = merge(local.common_tags, {
    Name = each.value.name
    Role = each.value.variant
  })
}
```

### Step 1.6: Makefile Integration

**Add to aws-accounts/Makefile**:
```makefile
# Cost Management
.PHONY: nuke-costs list-costs

list-costs:
	@echo "=== CozyStack Demo Resources ==="
	@aws ec2 describe-instances --region eu-west-1 \
		--filters "Name=tag:Demo,Values=cozystack-moon-and-back" \
		--query 'Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType,Tags[?Key==`Name`].Value|[0]]' \
		--output table

nuke-costs:
	@echo "⚠️  WARNING: Terminating ALL demo instances"
	@read -p "Type 'DESTROY' to confirm: " confirm && [ "$$confirm" = "DESTROY" ] || exit 1
	@aws ec2 describe-instances --region eu-west-1 \
		--filters "Name=tag:Demo,Values=cozystack-moon-and-back" "Name=instance-state-name,Values=running,stopped" \
		--query 'Reservations[*].Instances[*].InstanceId' \
		--output text | xargs -r aws ec2 terminate-instances --instance-ids
	@tofu destroy -target=module.cozy_demo -var-file=sb.tfvars -state=sb.tfstate -auto-approve
	@echo "✅ All demo resources terminated"
```

## Phase 2: Cluster Bootstrap

### Step 2.1: Verify Talos Nodes Booted

```bash
# After instances launch and reboot
talosctl -n 10.10.0.101 version
talosctl -n 10.10.0.102 version  
talosctl -n 10.10.0.103 version
```

### Step 2.2: Generate Machine Configs

From cozystack-moon-and-back repo:
```bash
# Use talm to generate configs
talm gen config \
  --cluster-name cozy-demo \
  --endpoint 10.10.0.101:6443 \
  --nodes 10.10.0.101,10.10.0.102,10.10.0.103
```

### Step 2.3: Apply Configurations

```bash
# Bootstrap first control plane node
talosctl -n 10.10.0.101 apply-config --file controlplane.yaml

# Apply to other nodes
talosctl -n 10.10.0.102 apply-config --file worker.yaml
talosctl -n 10.10.0.103 apply-config --file worker.yaml

# Bootstrap cluster
talosctl -n 10.10.0.101 bootstrap
```

### Step 2.4: Get Kubeconfig

```bash
talosctl -n 10.10.0.101 kubeconfig
kubectl get nodes
```

## Phase 3: CozyStack Installation

(Deferred - requires working Kubernetes cluster from Phase 2)

## Questions to Resolve

### Critical (Blocking)

1. **Subnet ID**: What's the actual subnet-id for 10.10.0.0/24?
   ```bash
   aws ec2 describe-subnets --filters "Name=cidr-block,Values=10.10.0.0/24"
   ```

2. **Existing Bastion**: Is bastion already running, or do we create it?
   - If exists: What's its instance ID for ENI attachment?
   - If new: Do we use ASG or single instance?

3. **Registry Strategy**: ECR pull-through cache or Docker registry:2?
   - ECR: More AWS-native, easier billing
   - Docker: Simpler, matches home lab

4. **Talos Images**: Verify GHCR path
   - Current: `ghcr.io/urmanac/cozystack-moon-and-back/talos-arm64-*:latest`
   - Are these already built and pushed?

### Medium Priority

5. **Security Groups**: Does `sg-0f9cb1bf403ae7dd1` exist for bastion?

6. **VPC ID**: Confirm `vpc-04af837e642c001c6` is sandbox VPC

7. **Key Pair**: Which EC2 key pair for emergency SSH?

8. **Tailscale Auth**: How to get Tailscale auth key for bastion?

## File Structure Changes

### aws-accounts Repository

```
aws-accounts/
├── modules/
│   └── cozy-demo/              # NEW - ALL demo infrastructure
│       ├── main.tf
│       ├── variables.tf
│       ├── outputs.tf
│       ├── bastion.tf
│       ├── talos-nodes.tf
│       ├── security-groups.tf
│       └── templates/
│           └── boot-to-talos.sh.tpl
├── main.tf                     # UPDATED - add cozy_demo module
├── sb.tfvars                   # UPDATED - add demo config
├── Makefile                    # UPDATED - add nuke-costs target
└── docs/
    └── cozystack-infrastructure-plan.md  # This file
```

### Integration Points

```hcl
# In main.tf
module "cozy_demo" {
  source = "./modules/cozy-demo"
  
  vpc_id                 = var.sandbox_vpc_id
  subnet_id              = var.sandbox_public_subnet_id
  bastion_security_groups = var.bastion_security_groups
  
  talos_nodes = {
    gateway = {
      name       = "talos-gateway-1"
      variant    = "gateway"
      private_ip = "10.10.0.101"
    }
    compute_1 = {
      name       = "talos-compute-2"
      variant    = "compute"
      private_ip = "10.10.0.102"
    }
    compute_2 = {
      name       = "talos-compute-3"
      variant    = "compute"
      private_ip = "10.10.0.103"
    }
  }
}
```

## Next Steps

1. **Answer Critical Questions** (especially subnet/VPC IDs)
2. **Create cozy-demo Module** in aws-accounts
3. **Test with `make plan-sb`** (no changes yet)
4. **Implement Registry Solution** (decide ECR vs Docker)
5. **Test boot-to-talos** on single node
6. **Scale to 3 nodes** once working
7. **Bootstrap Kubernetes cluster**
8. **Install CozyStack** (separate phase)

## Cost Estimates

**Daily Cost** (5 hours runtime):
- 3x t4g.medium: $0.0420/hr × 3 × 5 = $0.63/day
- EBS (3x 50GB): $0.08/GB/mo × 150GB / 30 = $0.40/day
- **Total**: ~$1.03/day or ~$31/month (at 5hr/day)

**Teardown**: `make nuke-costs` terminates everything immediately

## References

- [DESKTOP.md](../../cozystack-moon-and-back/docs/DESKTOP.md) - Original AWS design
- [DESKTOP-3-PLAN.md](../../cozystack-moon-and-back/docs/DESKTOP-3-PLAN.md) - Deployment understanding
- [get_mfa_session.sh](../get_mfa_session.sh) - AWS authentication
- [claude-mcp-aws-integration.md](./claude-mcp-aws-integration.md) - MCP usage (now disconnected)

---

**Status**: Ready for implementation pending critical question answers  
**Next Session**: Create cozy-demo module and test with `make plan-sb`
