# Implementation Ready - CozyStack Infrastructure

**Status**: ✅ All critical questions resolved  
**Date**: 2025-11-23  
**Next Action**: Create `modules/cozy-demo/` and test with `make plan-sb`

## Resolved Details

### Network Configuration ✅
- **VPC**: `vpc-04af837e642c001c6` (sandbox-eu-vpc, 10.10.0.0/16)
- **Subnet**: `subnet-0fb2c632ccc6d99e5` (sandbox-eu-public-0, 10.10.0.0/24)
- **IPv6**: `2a05:d018:106c:7800::/64` (bastion SSH via IPv6)
- **Route Table**: `rtb-0cbcf22ea88e98b03` (sandbox-eu-public-rt with IGW)

### Bastion Configuration ✅
- **Deployment**: ASG scaled 0→1 on schedule (7am-12pm or 8am-1pm)
- **Cost Pattern**: Deleted daily, only 5 hours/day = 83% cost savings
- **Registry**: Docker registry:2 on port 5000 (GHCR pull-through cache)
- **EBS Addition**: +50GB for registry cache = $0.83/month
- **Decision**: NO ECR (no free tier, would be ongoing cost)

### Talos Images ✅
```
Gateway (1 node):
  ghcr.io/urmanac/cozystack-assets/talos/cozystack-spin-tailscale/talos:v1.11.5

Compute (2 nodes):
  ghcr.io/urmanac/cozystack-assets/talos/cozystack-spin-only/talos:v1.11.5
```

## Implementation Steps

### Step 1: Create Module Structure
```bash
cd /path/to/aws-accounts
mkdir -p modules/cozy-demo/templates
```

### Step 2: Create Core Files

**modules/cozy-demo/main.tf**:
- Common tags with "Demo" = "cozystack-moon-and-back"
- Talos security group
- Launch templates (3 nodes)
- Reference existing bastion ENI

**modules/cozy-demo/variables.tf**:
- `vpc_id`, `subnet_id`, `bastion_security_groups`
- `talos_nodes` map with gateway + 2 compute
- `talos_image_tag` = "v1.11.5"

**modules/cozy-demo/outputs.tf**:
- Launch template IDs
- Security group ID
- Talos node IPs (for reference)

**modules/cozy-demo/templates/boot-to-talos.sh.tpl**:
- boot-to-talos installation script
- Static IP configuration
- Registry mirror setup (10.10.0.100:5000)

### Step 3: Integrate in Root
```hcl
# main.tf
module "cozy_demo" {
  source = "./modules/cozy-demo"
  
  vpc_id    = "vpc-04af837e642c001c6"
  subnet_id = "subnet-0fb2c632ccc6d99e5"
  
  bastion_security_groups = ["sg-0f9cb1bf403ae7dd1"]  # Verify this exists
  
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

### Step 4: Update Makefile
```makefile
.PHONY: list-costs nuke-costs

list-costs:
	@aws ec2 describe-instances --region eu-west-1 \
		--filters "Name=tag:Demo,Values=cozystack-moon-and-back" \
		--query 'Reservations[*].Instances[*].[InstanceId,State.Name,InstanceType,Tags[?Key==`Name`].Value|[0]]' \
		--output table

nuke-costs:
	@echo "⚠️  WARNING: Terminating ALL demo instances"
	@read -p "Type 'DESTROY' to confirm: " confirm && [ "$$confirm" = "DESTROY" ] || exit 1
	@aws ec2 describe-instances --region eu-west-1 \
		--filters "Name=tag:Demo,Values=cozystack-moon-and-back" \
		"Name=instance-state-name,Values=running,stopped" \
		--query 'Reservations[*].Instances[*].InstanceId' \
		--output text | xargs -r aws ec2 terminate-instances --instance-ids
	@tofu destroy -target=module.cozy_demo -var-file=sb.tfvars -state=sb.tfstate -auto-approve
```

### Step 5: Test Without Changes
```bash
# Authenticate
source get_mfa_session.sh
export AWS_PROFILE=sb-bootstrap
aws_mfa
save_mfa

# Test Terraform plan
make plan-sb
# Should show: no changes (module doesn't exist yet)
```

### Step 6: Apply Infrastructure
```bash
# Create the module resources
make apply-sb

# Expected: Launch templates created, security group created
# NO instances launched yet (we do that manually)
```

### Step 7: Manual Instance Launch

**First ensure bastion is running**:
```bash
# Check if bastion is scaled up
aws ec2 describe-instances --region eu-west-1 \
  --filters "Name=tag:Name,Values=*bastion*" \
  "Name=instance-state-name,Values=running"

# If not running and outside scheduled hours, manually scale ASG:
aws autoscaling set-desired-capacity --region eu-west-1 \
  --auto-scaling-group-name <bastion-asg-name> \
  --desired-capacity 1

# Wait for bastion to be ready (registry cache up)
# ssh into bastion and check: docker ps | grep ghcr-cache
```

**Launch Talos nodes**:
```bash
# Get launch template names
aws ec2 describe-launch-templates --region eu-west-1 \
  --filters "Name=tag:Demo,Values=cozystack-moon-and-back"

# Launch gateway node
aws ec2 run-instances --region eu-west-1 \
  --launch-template LaunchTemplateName=cozy-talos-talos-gateway-1-... \
  --count 1 \
  --private-ip-address 10.10.0.101

# Launch compute nodes (repeat for each)
aws ec2 run-instances --region eu-west-1 \
  --launch-template LaunchTemplateName=cozy-talos-talos-compute-2-... \
  --count 1 \
  --private-ip-address 10.10.0.102
```

### Step 8: Monitor boot-to-talos
```bash
# Watch instances boot
watch -n 5 'aws ec2 describe-instances --region eu-west-1 \
  --filters "Name=tag:Demo,Values=cozystack-moon-and-back" \
  --query "Reservations[*].Instances[*].[Tags[?Key==\`Name\`].Value|[0],State.Name,PrivateIpAddress]"'

# After 5-10 minutes, verify Talos API responding
talosctl -n 10.10.0.101 version
talosctl -n 10.10.0.102 version
talosctl -n 10.10.0.103 version
```

## Remaining Questions (Medium Priority)

1. **Bastion Security Group**: Does `sg-0f9cb1bf403ae7dd1` exist?
   ```bash
   aws ec2 describe-security-groups --region eu-west-1 \
     --group-ids sg-0f9cb1bf403ae7dd1
   ```

2. **EC2 Key Pair**: Which key pair for emergency SSH access?
   ```bash
   aws ec2 describe-key-pairs --region eu-west-1
   ```

3. **Bastion ASG Name**: For manual scaling if needed
   ```bash
   aws autoscaling describe-auto-scaling-groups --region eu-west-1 \
     --query 'AutoScalingGroups[?contains(Tags[?Key==`Name`].Value,`bastion`)]'
   ```

## Cost Summary

**Per-Hour Costs** (while running):
- 3x t4g.medium: $0.0420/hr × 3 = $0.126/hr
- EBS storage (prorated): negligible
- **Total**: ~$0.13/hr or ~$0.65 for 5-hour session

**Monthly Costs** (5 hours/day):
- EC2: $0.126/hr × 5 × 30 = $18.90/month
- EBS: $0.08/GB × 200GB × 0.208 = $3.33/month
- Bastion registry cache: +$0.83/month
- **Total**: ~$23/month

**Emergency Teardown**: `make nuke-costs` (requires typing "DESTROY")

## Success Criteria

✅ **Phase 1 Complete When**:
- `make plan-sb` shows module resources
- `make apply-sb` creates launch templates + security group
- NO unexpected costs (no running instances yet)

✅ **Phase 2 Complete When**:
- 3 instances running (1 gateway, 2 compute)
- All nodes respond to `talosctl version`
- boot-to-talos logs show successful installation

✅ **Phase 3 Complete When**:
- Kubernetes cluster formed (3 nodes Ready)
- kubectl access from bastion/tailscale
- Gateway node advertises subnet via Tailscale

## References

- [Full Implementation Plan](./cozystack-infrastructure-plan.md)
- [Original AWS Design](../../cozystack-moon-and-back/docs/DESKTOP.md)
- [AWS MCP Integration](./claude-mcp-aws-integration.md)

---

**Ready to proceed**: Yes, all blockers resolved  
**Start with**: Create module directory structure
