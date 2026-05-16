# Talos Lab: ARM64 CozyStack on AWS

So you've run `make apply-sb`, the bastion is at `10.10.1.100`, IPv4 egress is
working through WireGuard, and the registry caches are serving on ports 5050–5054.
Here's how to bring up Talos nodes and run CozyStack on top.

---

## Why private IPv4?

Talos does not speak IPv6 natively for cluster communication. The Kubernetes API
endpoint, etcd, kubelet, and the Talos API (port 50000) all operate on IPv4.
The nodes have no public IPv4 addresses. Everything inside the cluster stays on
the `10.10.1.0/24` private subnet — accessible from the bastion over the same
network.

This means the bastion is the only management path. All `talosctl` and `kubectl`
commands run from there.

---

## Infrastructure already in place

These come from `make apply-sb` (outputs in `sb.tfstate`):

| Resource | Value |
|---|---|
| VPC | `vpc-04af837e642c001c6` |
| Private subnet | `subnet-07a140ab2b20bf89b` (`10.10.1.0/24`) |
| Talos security group | `sg-0e6b4a78092854897` |
| Registry cache (ghcr.io) | `10.10.1.100:5054` |
| All registries | `10.10.1.100:5050–5054` |

---

## Images

Published by [urmanac/cozystack-moon-and-back](https://github.com/urmanac/cozystack-moon-and-back)
to GHCR. Two variants for the two node roles:

| Variant | Image | Purpose |
|---|---|---|
| spin-tailscale | `ghcr.io/urmanac/cozystack-assets/talos/cozystack-spin-tailscale/talos:latest` | Gateway node — subnet router via Tailscale |
| spin-only | `ghcr.io/urmanac/cozystack-assets/talos/cozystack-spin-only/talos:latest` | Compute nodes — Spin WASM runtime only |

---

## Step 1: Launch nodes in maintenance mode

Use the **official upstream Talos AMI** — no user-data. This is the key insight:
booting the upstream AMI without any user-data drops it directly into Talos
maintenance mode, where `talosctl` can reach and configure it.

```bash
# Official Talos v1.11.5 ARM64 AMI (eu-west-1)
TALOS_AMI="ami-07898be81f2028262"
REGION="eu-west-1"
SECURITY_GROUP="sg-0e6b4a78092854897"
SUBNET_ID="subnet-07a140ab2b20bf89b"

# 1 gateway node
aws ec2 run-instances \
  --region $REGION \
  --image-id $TALOS_AMI \
  --instance-type c7g.large \
  --security-group-ids $SECURITY_GROUP \
  --subnet-id $SUBNET_ID \
  --private-ip-address 10.10.1.101 \
  --ipv6-address-count 1 \
  --no-associate-public-ip-address \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":20,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=talos-gateway}]' \
  --query 'Instances[0].InstanceId' --output text

# 2 compute nodes (repeat with 10.10.1.102, 10.10.1.103)
aws ec2 run-instances \
  --region $REGION \
  --image-id $TALOS_AMI \
  --instance-type c7g.large \
  --security-group-ids $SECURITY_GROUP \
  --subnet-id $SUBNET_ID \
  --private-ip-address 10.10.1.102 \
  --ipv6-address-count 1 \
  --no-associate-public-ip-address \
  --block-device-mappings '[{"DeviceName":"/dev/xvda","Ebs":{"VolumeSize":20,"VolumeType":"gp3","DeleteOnTermination":true}}]' \
  --tag-specifications 'ResourceType=instance,Tags=[{Key=Name,Value=talos-compute-1}]' \
  --query 'Instances[0].InstanceId' --output text
```

---

## Step 2: Generate and apply Talos config (from bastion)

SSH to the bastion, then install `talosctl` and generate configs.

```bash
ssh ec2-user@<bastion-ipv6>

# Install talosctl on bastion (ARM64)
curl -sL https://github.com/siderolabs/talos/releases/download/v1.11.5/talosctl-linux-arm64 \
  -o talosctl && chmod +x talosctl && sudo mv talosctl /usr/local/bin/

# Write the patch for AWS NTP and registry mirrors
cat > time-server-patch.yaml << 'EOF'
machine:
  time:
    servers:
      - 169.254.169.123
  registries:
    mirrors:
      ghcr.io:
        endpoints:
          - http://10.10.1.100:5054
      docker.io:
        endpoints:
          - http://10.10.1.100:5050
    config:
      10.10.1.100:5054:
        tls:
          insecureSkipVerify: true
      10.10.1.100:5050:
        tls:
          insecureSkipVerify: true
EOF

# Generate config — use the gateway node's known IPv4 as the cluster endpoint
talosctl gen config talos-cozystack-cluster https://10.10.1.101:6443 \
    --with-examples=false \
    --with-docs=false \
    --with-kubespan \
    --install-disk /dev/xvda \
    --config-patch '@time-server-patch.yaml'

# Point talosctl at the cluster
export TALOSCONFIG=$(pwd)/talosconfig
talosctl config endpoint 10.10.1.101
talosctl config nodes 10.10.1.101

# Apply the controlplane config to the gateway node (in maintenance mode)
talosctl apply-config --insecure --nodes 10.10.1.101 --file controlplane.yaml

# Apply worker config to compute nodes
talosctl apply-config --insecure --nodes 10.10.1.102 --file worker.yaml
talosctl apply-config --insecure --nodes 10.10.1.103 --file worker.yaml

# Wait ~2 minutes for the node to reboot into configured state, then bootstrap
talosctl bootstrap

# Watch health
talosctl health

# Retrieve kubeconfig
talosctl kubeconfig .
export KUBECONFIG=$(pwd)/kubeconfig
kubectl get nodes
```

---

## Step 3: Upgrade to CozyStack image

Once the cluster is healthy, upgrade each node to the custom CozyStack image.
This was the embarrassingly obvious step that took us a long time to find:
**`talosctl upgrade`**. It performs a rolling image swap and reboot, preserving
cluster state.

```bash
# Upgrade the gateway node to the spin-tailscale variant
talosctl upgrade \
  --nodes 10.10.1.101 \
  --image ghcr.io/urmanac/cozystack-assets/talos/cozystack-spin-tailscale/talos:latest \
  --wait

# Upgrade compute nodes to the spin-only variant
talosctl upgrade \
  --nodes 10.10.1.102 \
  --image ghcr.io/urmanac/cozystack-assets/talos/cozystack-spin-only/talos:latest \
  --wait

talosctl upgrade \
  --nodes 10.10.1.103 \
  --image ghcr.io/urmanac/cozystack-assets/talos/cozystack-spin-only/talos:latest \
  --wait

# Confirm extensions are loaded
talosctl -n 10.10.1.101 get extensions
# Should show: spin, tailscale

talosctl -n 10.10.1.102 get extensions
# Should show: spin
```

The upgrade pulls through the bastion's registry cache (`10.10.1.100:5054`
for `ghcr.io`), so no direct internet egress is needed from the Talos nodes.

---

## Teardown

```bash
# Terminate all three Talos nodes
aws ec2 terminate-instances --region eu-west-1 \
  --instance-ids <gateway-id> <compute-1-id> <compute-2-id>
```

The bastion and VPC are unaffected. Run `make apply-sb` again whenever you want
to bring a fresh cluster up.

---

## What was proven to work (2025-11-30)

Validated on a single-node cluster (`c7g.large`, `10.10.1.119`, `eu-west-1`):

- ✅ Official Talos AMI boots to maintenance mode with no user-data
- ✅ `talosctl apply-config` + `talosctl bootstrap` from bastion
- ✅ `talosctl upgrade` to custom CozyStack spin-tailscale image
- ✅ Registry cache pull-through for all 5 mirrors
- ✅ Spin WASM workloads run on ARM64 Graviton
- ✅ Kubernetes v1.34.1 on Talos v1.11.5 (ARM64)

The full 3-node cluster with CozyStack operator, Harvey tenant cluster, and
Crossplane was the next step — reached for the December 2025 CozySummit demo.

The images are currently built against **CozyStack v1.3.3** (as of May 2026).
See [urmanac/cozystack-moon-and-back](https://github.com/urmanac/cozystack-moon-and-back)
for current build status and image coordinates.
