# WireGuard Redundancy: Primary vs. Fallback Endpoints

## Context

The bastion host is IPv6-only (no public IPv4). It obtains IPv4 egress via a
WireGuard tunnel with two configured endpoints:

1. **Primary**: RIT CSH (`martyfunkhouser`) — fast, reliable, preferred (~160ms)
2. **Fallback**: Home DD-WRT router — used when primary is down (~210ms)

The primary endpoint is hosted in a dorm server room at RIT (Rochester Institute
of Technology) and goes offline **every summer when the dorm loses power**
(typically late May–August). The home router serves as a fallback during those
outages.

Both endpoints are configured as **redundant peers** using the same WireGuard
private key. Switching between them is just a matter of changing the `Endpoint`
address in the bastion's WireGuard config.

### `.env` / `.env.summer` convention

Two separate env files hold the WireGuard server variables. Both are in
`.gitignore` (they contain the bastion private key):

| File | Endpoint | When used |
|---|---|---|
| `.env` | RIT CSH primary | Default (Sept–May) |
| `.env.summer` | Home DD-WRT fallback | June–August when RIT is offline |

To swap for summer (when RIT goes offline):

```bash
mv .env .env.rit && mv .env.summer .env
# Rebuild bastion so new endpoint is baked in:
tofu apply -var-file=sb.tfvars -state=sb.tfstate -target='module.bastion_ci'
```

To revert at end of summer:

```bash
mv .env .env.summer && mv .env.rit .env
tofu apply -var-file=sb.tfvars -state=sb.tfstate -target='module.bastion_ci'
```

You can also switch the live bastion without a rebuild using `wg set` — see
the switching sections below.

---

## Primary endpoint: RIT CSH-hosted `martyfunkhouser`

The primary WireGuard endpoint is a VM in the Rochester Institute of Technology
(RIT) Computer Science House (CSH) dorm. This is the preferred endpoint because
it offers low latency and is more reliable during the academic year.

**Note**: This VM goes offline every summer (late May–August) when the dorm loses
power during break. The home DD-WRT fallback is deployed for those periods.

### Configuration

Configured in `.env` / `sb.tfvars`:

| Variable | Value |
|---|---|
| `MY_WIREGUARD_SERVER_PUB` | `gqrzji2A1YkREKl7bDsh+xk7fCuekTAGdLl8mNA+p1A=` |
| `MY_WIREGUARD_SERVER_IPV6` | `2620:8d:8000:e49:a00:27ff:fe2f:b6d9` |

### Endpoint details

- **Host**: `martyfunkhouser` (RIT CSH)
- **IPv6 WireGuard endpoint**: `2620:8d:8000:e49:a00:27ff:fe2f:b6d9:51820`
- **NAT egress**: exits via RIT network
- **Performance**: low latency (~10–50ms from bastion)
- **Availability**: online September–May, offline June–August

### Known outages

- **2026 summer**: offline (dorm powered down)

---

## Fallback endpoint: Home DD-WRT Router

When the primary RIT endpoint is offline (summer), the home DD-WRT router
provides the fallback WireGuard server.

### Router details

| Item | Value |
|---|---|
| IPv4 WAN | `98.32.232.82` |
| IPv6 WAN | `2601:245:c700:e:fe34:97ff:fe03:1ec0` (dynamic — check DD-WRT Status page) |
| **Router WireGuard public key** | `OPNxgeBRyQ6jpyfhucAG4QVjUIS2llSEQOWh6xLhSmY=` |
| **Router WireGuard private key** | stored in DD-WRT only — never exported |
| Tunnel listen port | `51820` |

> The router public key was generated on 2026-05-16. If DD-WRT is factory-reset
> or the tunnel is deleted and regenerated, a new keypair is created and this
> key becomes invalid.

### DD-WRT tunnel settings

In the WireGuard tunnel UI:

| Field | Value |
|---|---|
| Protocol Type | WireGuard |
| NAT via Tunnel | ✓ (critical — NATs IPv4 traffic out WAN) |
| CVE-2019-14899 Mitigation | ✓ |
| Firewall Inbound | ✓ (opens UDP 51820 on WAN) |
| Kill Switch | unchecked |
| Listen Port | `51820` |
| MTU | `1420` |
| IP Addresses / Netmask (CIDR) | `10.66.66.1/24` |

### Peer entry for bastion

| Field | Value |
|---|---|
| Peer Name | `bastion` |
| Public Key | `FSN4y6aRNuYT1uI40SkCloBvqS+jc6hZ1z0LPHVQVUA=` |
| Allowed IPs | `10.66.66.2/32` |
| Endpoint | *(blank — bastion initiates)* |
| Persistent Keepalive | `25` |

### Updating `.env` for the fallback (temporary)

When the primary RIT endpoint goes offline, patch the bastion to use the home
router as the fallback:

```sh
MY_WIREGUARD_SERVER_PUB=OPNxgeBRyQ6jpyfhucAG4QVjUIS2llSEQOWh6xLhSmY=
MY_WIREGUARD_SERVER_IPV6=2601:245:c700:e:fe34:97ff:fe03:1ec0
```

> ⚠ The router IPv6 WAN address is dynamic — verify it in DD-WRT Status before
> using. If it changed, update `MY_WIREGUARD_SERVER_IPV6` and patch the live
> bastion wg0.conf (see below).

**Note**: This is a temporary fallback during RIT's summer shutdown. Switch back
to the primary when it comes online in autumn.

### Patching the live bastion (no reboot)

SSH to bastion, then:

```sh
sudo wg set wg0 peer <OLD_SERVER_PUB> remove
sudo wg set wg0 peer OPNxgeBRyQ6jpyfhucAG4QVjUIS2llSEQOWh6xLhSmY= \
  endpoint [2601:245:c700:e:fe34:97ff:fe03:1ec0]:51820 \
  allowed-ips 0.0.0.0/1,128.0.0.0/1,10.66.66.0/24 \
  persistent-keepalive 25
# Persist for reboots:
sudo wg showconf wg0 | sudo tee /etc/wireguard/wg0.conf
```

Also update `MY_WIREGUARD_SERVER_PUB` and `MY_WIREGUARD_SERVER_IPV6` in `.env`
and do a `make apply-sb` so the next bastion rebuild bakes in the right endpoint.

### IPv6 firewall note

⚠ **Important security finding (discovered 2026-05-16):**  
With DHCPv6-PD active, LAN devices receive globally-routable IPv6 addresses
(e.g. `2601:245:c700:e:211:32ff:fe6f:4763`). These are reachable from the
internet. DD-WRT does **not** block new inbound connections by default.

A comprehensive firewall script has been deployed — see
[`docs/ipv6-firewall-ddwrt.md`](ipv6-firewall-ddwrt.md) for full details,
including the critical DHCPv6 allow rule that must accompany the DROP rules.

**TL;DR**: `KPB_V6_INPUT` and `KPB_V6_FWD` chains in `rc_firewall` (NVRAM)
allow UDP/51820 and ESTABLISHED/RELATED inbound on WAN, drop everything else
new. DHCPv6 (UDP src:547 dst:546) is explicitly allowed before the DROP rule.

---

## Enabling the DD-WRT WireGuard server

The tunnel was configured via **Setup → Tunnels → WireGuard** in the UI. To
re-enable it after a factory reset, or to verify it is running:

```sh
ssh root@10.17.12.1 'wg show'
```

Expected output shows interface `wg0` with the router's public key, bastion
peer, and a handshake timestamp if the tunnel is active. If no output, the
WireGuard interface is down — go to the DD-WRT UI and ensure the tunnel is
enabled, then click **Save** and **Apply Settings**.

### Activating from the bastion side

With the DD-WRT WireGuard server running, update the bastion to point at the
router instead of the university endpoint:

```sh
# Patch live (no reboot required)
sudo wg set wg0 peer gqrzji2A1YkREKl7bDsh+xk7fCuekTAGdLl8mNA+p1A= remove
sudo wg set wg0 peer OPNxgeBRyQ6jpyfhucAG4QVjUIS2llSEQOWh6xLhSmY= \
  endpoint [2601:245:c700:e:fe34:97ff:fe03:1ec0]:51820 \
  allowed-ips 0.0.0.0/1,128.0.0.0/1,10.66.66.0/24 \
  persistent-keepalive 25
sudo wg showconf wg0 | sudo tee /etc/wireguard/wg0.conf

# Verify connectivity
wg show wg0
curl -4 ifconfig.me   # should return router's IPv4 WAN IP (98.32.232.82)
```

### Making the switch permanent (Terraform)

Swap `.env` files and rebuild the bastion:

```bash
mv .env .env.rit && mv .env.summer .env
tofu apply -var-file=sb.tfvars -state=sb.tfstate -target='module.bastion_ci'
```

> ⚠ The router IPv6 WAN address is dynamic. Verify it in DD-WRT Status before
> rebuilding, and update `MY_WIREGUARD_SERVER_IPV6` in `.env.summer` if it changed.

### Switching back to the primary (end of summer)

When the RIT endpoint comes back online, revert to the primary endpoint:

```sh
sudo wg set wg0 peer OPNxgeBRyQ6jpyfhucAG4QVjUIS2llSEQOWh6xLhSmY= remove
sudo wg set wg0 peer gqrzji2A1YkREKl7bDsh+xk7fCuekTAGdLl8mNA+p1A= \
  endpoint [2620:8d:8000:e49:a00:27ff:fe2f:b6d9]:51820 \
  allowed-ips 0.0.0.0/1,128.0.0.0/1,10.66.66.0/24 \
  persistent-keepalive 25
sudo wg showconf wg0 | sudo tee /etc/wireguard/wg0.conf
```

Also swap the env files back and rebuild:

```bash
mv .env .env.summer && mv .env.rit .env
tofu apply -var-file=sb.tfvars -state=sb.tfstate -target='module.bastion_ci'
```

---

## Redundancy and switching

Both WireGuard endpoints are configured as **redundant peers** using the same
bastion private key. The bastion can reach either endpoint without re-keying.

Switching is just an `endpoint` change:

- **RIT primary**: `[2620:8d:8000:e49:a00:27ff:fe2f:b6d9]:51820`
- **Home fallback**: `[2601:245:c700:e:fe34:97ff:fe03:1ec0]:51820`

Both accept the peer key `FSN4y6aRNuYT1uI40SkCloBvqS+jc6hZ1z0LPHVQVUA=` on the
bastion side, and both serve as NAT gateways for IPv4 egress.

---

## Validation: Home DD-WRT fallback (2026-05-16)

Tested and confirmed:

```sh
# Bastion can reach both LAN and WAN via the home router tunnel
ssh ec2-user@2a05:d018:106c:7801:ab08:3c88:efcd:f985 '
  ping 10.66.66.1 -c 1                          # tunnel IP
  ping 10.17.12.1 -c 1                          # router LAN private IP
  curl -4 --max-time 8 ifconfig.me              # should be 98.32.232.82 (home WAN)
'

# Bastion can reach public IPv4 internet through the tunnel
ssh ec2-user@2a05:d018:106c:7801:ab08:3c88:efcd:f985 '
  ping 4.208.26.196 -c 2                        # ghcr.io public IP
'

# Router public SSH is not reachable from bastion's public network
ssh ec2-user@2a05:d018:106c:7801:ab08:3c88:efcd:f985 '
  python3 -c "import socket; s = socket.socket(); s.settimeout(4); \
    s.connect(('2601:245:c700:e:fe34:97ff:fe03:1ec0', 22, 0, 0))"
# Expected: timed out (good)
'
```

Results:

- ✅ Tunnel ping succeeds
- ✅ Router LAN IP is reachable (but not other private subnets — isolation working)
- ✅ IPv4 egress exits via home WAN (`98.32.232.82`)
- ✅ Public IPv4 internet is reachable
- ✅ Public SSH to router is blocked

This validates the home DD-WRT fallback is operational and provides both network
isolation (other private subnets inaccessible) and public reachability for the
bastion's container pulls.
