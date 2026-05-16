# Talos Lab Runbook — what worked, what didn't

Last run: **2026-05-16**. Branch: `revive-test-urmanac-org`.

This is the operational companion to [README.md](README.md). The README
describes the architecture; this file is the cookbook for the next attempt.

---

## Current state at end of session

- 3-node Talos v1.12.7 ARM64 cluster (`cozyaws`) was up and healthy
- CozyStack operator v1.3.3 was installed via helm and running
- Flux pods (`flux`, `flux-tenants`) were scheduling in `cozy-fluxcd`
- `cozystack.cozystack-platform` Package was applied but stuck
- All three nodes are about to be terminated — disposable lab

### Inventory

| Node | Private IP | Instance ID | Role |
|---|---|---|---|
| talos-gateway | 10.10.1.101 | `i-0832313090b2500c3` | controlplane |
| talos-compute-1 | 10.10.1.102 | `i-0262c763e74145fd0` | worker |
| talos-compute-2 | 10.10.1.103 | `i-0c814020a6ac0ca33` | worker |

All built from `ami-004622e65b38b994c` (talos-v1.12.7-eu-west-1-arm64,
released 2026-04-24).

---

## What actually worked (the talm-based flow)

The README's `talosctl gen config` flow is one valid path. **What we used
today and proved end-to-end is the [talm](https://github.com/cozystack/talm)
helm-based templater.** Backed up under [cozystack-cluster/](cozystack-cluster/).

### Recipe from a clean bastion

```bash
# 1. Clone the talm-based cluster project (private — see cozystack-cluster/
#    in this repo for the snapshot we used)
cd ~ && git clone <talm-cluster-repo> cozystack-cluster && cd cozystack-cluster

# 2. Render per-node configs (template.sh wraps `talm template`)
sudo dnf install -y make    # bastion ships without make
make gen                    # produces nodes/node1.yaml etc.

# 3. Apply -- order matters; --insecure for first apply to maintenance mode
talm apply -f nodes/node1.yaml -i
talm apply -f nodes/node2.yaml -i
talm apply -f nodes/node3.yaml -i

# 4. Bootstrap etcd on the controlplane node (one node only)
talm bootstrap -f nodes/node1.yaml

# 5. Watch nodes come up
talm dashboard -f nodes/node1.yaml -f nodes/node2.yaml -f nodes/node3.yaml

# 6. Pull kubeconfig
talm kubeconfig -f nodes/node1.yaml
mkdir -p ~/.kube && cp kubeconfig ~/.kube/config
kubectl get nodes
```

### Then install CozyStack

```bash
brew install helm    # bastion's dnf has no helm package

helm upgrade --install cozystack \
  oci://ghcr.io/cozystack/cozystack/cozy-installer \
  --version 1.3.3 \
  --namespace cozy-system --create-namespace \
  --set cozystackOperator.image=ghcr.io/urmanac/cozystack-assets/cozystack-operator:v1.3.3 \
  --set cozystackOperator.platformSourceUrl=oci://ghcr.io/urmanac/cozystack-assets/cozystack-packages \
  --set cozystackOperator.platformSourceRef=digest=sha256:cdc117a96b4f52e94e6f9bfd4c20660ae5ddcd66c9a0f8343151d042e98070b6

# Then apply the cozystack-platform Package
kubectl apply -f ~/package.yaml    # see ./package.yaml
```

Full historical command list: [bastion-shell-history.txt](bastion-shell-history.txt).

---

## Gotchas that cost us time today

### 1. Security group: ports 50000 and 6443 weren't open from bastion

The Talos SG (`sg-0e6b4a78092854897`) had port 50000 / 6443 open only from
itself (intra-cluster), not from the bastion SG. `talosctl` from bastion
hung with `i/o timeout`.

**Fix (already applied via CLI, NOT yet in Terraform):**

```bash
aws ec2 authorize-security-group-ingress --region eu-west-1 \
  --group-id sg-0e6b4a78092854897 \
  --ip-permissions '[
    {"IpProtocol":"tcp","FromPort":50000,"ToPort":50000,"UserIdGroupPairs":[{"GroupId":"sg-0f9cb1bf403ae7dd1","Description":"talosctl from bastion"}]},
    {"IpProtocol":"tcp","FromPort":6443,"ToPort":6443,"UserIdGroupPairs":[{"GroupId":"sg-0f9cb1bf403ae7dd1","Description":"kubectl from bastion"}]}
  ]'
```

**TODO**: codify these rules in
[modules/vpc/main.tf](../../modules/vpc/main.tf) so a `make apply-sb` after a
state wipe doesn't break this again.

### 2. Registry patch: `config:` block kills HTTP mirrors

Initial patch had `config: { "10.10.1.100:5051": { tls: { insecureSkipVerify: true } } }`
alongside `endpoints: [http://10.10.1.100:5051]`. Talos rejected it with:

```
TLS config specified for non-HTTPS registry: "10.10.1.100:5051"
```

The `config:` block is **only for HTTPS registries** that need a custom CA or
auth. For plain `http://` mirrors, omit the `config:` block entirely.

Working patch lives at [registry-patch.yaml](registry-patch.yaml).

### 3. Bastion didn't have `make` or `helm` preinstalled

Add to bastion userdata:
- `dnf install -y make`
- Pull a `helm` binary directly (avoid the brew detour; brew on Amazon Linux
  pulls in a lot)

### 4. `talm apply -i` is mandatory on first apply

The first apply against a maintenance-mode node must use `-i` (insecure). The
templates have it documented but it's easy to miss.

### 5. node{2,3}.yaml needed manual edits after `make gen`

Per the history, several rounds of `vi nodes/node*.yaml` were needed before
nodes 2 and 3 would accept their config. Likely candidates: per-node IP
overrides, role tags. **Check templates/worker.yaml in cozystack-cluster/
against what was actually applied** — diff `nodes/node2.yaml` against a
fresh `make gen` output.

### 6. `kernelModuleSpec` errors are cosmetic

These warnings during boot are harmless — drbd/spl/zfs aren't loaded because
they're not present in the spin-only/spin-tailscale variants:

```
error loading module "drbd": module not found
error loading module "spl": module not found
error loading module "zfs": module not found
```

The cluster reaches Ready despite these. Don't chase them.

---

## SOLVED: OCIRepository via the bastion registry cache

Initial problem: `cozystack-platform` HelmRelease stuck because Flux's
OCIRepository couldn't reach `ghcr.io`:

```
OCIRepository/cozy-system/cozystack-platform: failed to pull artifact:
  Get "https://ghcr.io/v2/": dial tcp 4.208.26.196:443: i/o timeout
```

Talos's `machine.registries.mirrors` block routes **containerd image pulls**
through the bastion proxy. Flux's OCIRepository source controller does HTTPS
calls from inside the pod and bypasses containerd's mirror config entirely.
Pods have no IPv4 egress.

### Fix

Point the OCIRepository at the bastion proxy directly and mark it insecure
(plain HTTP, no TLS verify):

```yaml
apiVersion: source.toolkit.fluxcd.io/v1
kind: OCIRepository
metadata:
  name: cozystack-packages
  namespace: cozy-system
spec:
  insecure: true                              # <-- the key flag
  url: oci://10.10.1.100:5054/urmanac/cozystack-assets/cozystack-packages
  # ... ref/digest unchanged
```

```bash
kubectl -n cozy-system annotate ocirepository cozystack-packages \
  reconcile.fluxcd.io/requestedAt="$(date +%s)" --overwrite
```

Both `cozystack-packages` and `cozystack-platform` OCIRepositories then
flipped to `True` and pulled the artifact from the bastion's `ghcr.io`
pull-through cache (`10.10.1.100:5054`). Cilium daemonset rolled out,
flux-tenants started spinning up.

### TODO: bake this in

The cozystack helm install needs flags (or values overrides) to set both
`url` to the bastion proxy and `insecure: true` on the OCIRepository(s) it
creates. Currently this was patched live with `kubectl edit`. Look for the
cozystack-operator settings that produce these OCIRepositories — likely
`platformSourceUrl` (already passed) plus a new `platformSourceInsecure`
or equivalent flag.

---

## Teardown

```bash
aws ec2 terminate-instances --region eu-west-1 \
  --instance-ids i-0832313090b2500c3 i-0262c763e74145fd0 i-0c814020a6ac0ca33
```

The bastion + VPC + SG rules stay. Next cluster picks the same IPs
(10.10.1.101–103) since the IP reservation is just the ENI on a terminated
instance and gets released within ~60s of termination.

---

## Gotcha 7: all-traffic SG rule required for kube-ovn / OVN

After cilium came up, kube-ovn deployed but its controller (on 10.10.1.103) could
not connect to the OVN Northbound database (on 10.10.1.101) on port 6641 SSL:

```
failed to connect to OVN_Northbound database ssl:[10.10.1.101]:6641: i/o timeout
```

The Talos SG had only 5 specific intra-cluster ports: 6443, 2379, 10250, 50000,
50001. kube-ovn additionally needs 6641/6642 (OVN NB/SB databases), 6644 (OVN
SB raft), 6081/udp (Geneve overlay), and potentially more. Rather than enumerate
them all, the correct fix (and standard practice for any K8s cluster SG) is a
single self-referencing all-traffic rule:

```bash
aws ec2 authorize-security-group-ingress --region eu-west-1 \
  --group-id sg-0e6b4a78092854897 \
  --ip-permissions '[{
    "IpProtocol": "-1",
    "UserIdGroupPairs": [{
      "GroupId": "sg-0e6b4a78092854897",
      "Description": "all traffic between Talos nodes (cluster-internal)"
    }]
  }]'
```

Once applied kube-ovn recovered immediately. **TODO: add this rule to Terraform.**

## Gotcha 8: ImagePullBackOff on first-seen images is transient

metallb (and other operators) showed `ImagePullBackOff` shortly after
installing. Not a bad image reference — the bastion's `registry:2`
pull-through cache takes 30–60 seconds to warm up for an image it has never
fetched. The pod retried and succeeded once the proxy had cached it. Don't
chase ImagePullBackOff errors immediately; wait 60 seconds first.

## CozyStack platform install state (2026-05-16, ~35 min after helm install)

`kg hr` snapshot showing how far the isp-full variant gets with 3 ×
`c7g.large` ARM64 nodes and all images pulled through the bastion proxy:

**True (installed successfully, 31 HelmReleases):**
- cilium, cilium-networkpolicy
- kubeovn ✅ (after SG fix)
- metallb, multus, metrics-server
- cert-manager-crds, vertical-pod-autoscaler-crds, prometheus-operator-crds
- grafana-operator, kafka-operator, kubevirt-operator, kubevirt-cdi-operator
- backup-controller, backupstrategy-controller, objectstorage-controller, reloader
- application-definition-crd, bucket-rd, http-cache-rd, info-rd, ingress-rd,
  kafka-rd, mongodb-rd, nats-rd, openbao-rd, seaweedfs-rd, tcp-balancer-rd,
  vpn-rd, cozystack-platform

**Blocked on cert-manager (cert-manager-crds True, cert-manager deploying):**
- cert-manager, cert-manager-issuers
- capi-operator (needs Certificate CRD) → all capi-providers-*
- kamaji (needs Certificate CRD)
- etcd-operator, flux-plunger, foundationdb-operator, mariadb-operator,
  mongodb-operator, victoria-metrics-operator, vertical-pod-autoscaler
- kubeovn-plunger, kubeovn-webhook

**Blocked on kubeovn (now ready — should cascade):**
- piraeus-operator-crds → piraeus-operator → linstor → linstor-scheduler
  → cozystack-scheduler
- postgres-operator, harbor-rd, monitoring-rd, rabbitmq-rd, redis-rd,
  snapshot-controller, tenant-rd, postgres-rd, rabbitmq-rd, redis-rd

**Blocked on cozystack-controller (needs ApplicationDefinition CRD to settle):**
- cozystack-api → dashboard, cozystack-basics, lineage-controller-webhook
- etcd-rd, qdrant-rd, virtualprivatecloud-rd (ApplicationDefinition CRD
  installed but cozystack-controller not yet ready)

**Key insight**: cert-manager is the primary remaining blocker. Once it comes
up it will cascade to ~20 more HelmReleases. The kubeovn unblock also cascades
to ~10 more. This cluster was genuinely progressing toward full isp-full
platform readiness on ARM64 Graviton with no public IPv4.

## Open TODOs

- [ ] **Terraform**: codify in `modules/vpc/main.tf`:
  - Port 50000 + 6443 ingress from bastion SG (`sg-0f9cb1bf403ae7dd1`) to Talos SG
  - All-traffic self-referencing rule within Talos SG (cluster-internal)
- [ ] Add `make` (and a pre-downloaded `helm` binary) to bastion userdata
- [ ] Find the cozystack helm value that makes the operator emit
  OCIRepositories already pointed at `10.10.1.100:5054` with
  `insecure: true` — avoid the live `kubectl edit` patch on each deploy
- [ ] Decide whether to commit the `talm` cluster project as a git
  submodule or sibling repo, rather than the snapshot in
  cozystack-cluster/
- [ ] Follow up: did cert-manager finish deploying and cascade to kamaji /
  capi-operator / etcd-operator? Did linstor complete after kubeovn unblock?
  Would need another session with a fresh cluster to confirm full platform.
