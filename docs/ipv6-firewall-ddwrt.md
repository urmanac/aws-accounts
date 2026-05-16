# IPv6 Firewall Hardening on DD-WRT

## Background

When DHCPv6-PD is enabled on DD-WRT, the ISP delegates a `/64` prefix
(currently `2601:245:c700:e::/64`) and every LAN device gets a globally-
routable IPv6 address via SLAAC. Unlike IPv4, there is no NAT — devices are
directly reachable from the public internet.

DD-WRT does include some default ip6tables rules, but they do not block new
inbound connections on the WAN interface. This was verified on firmware r64764
(2026-05-08) on an Asus RT-AC88U.

---

## Deployed firewall script

Saved to NVRAM as `rc_firewall` via **Administration → Commands → Save Firewall**.
Applied automatically on boot and after `stopservice firewall`.

```sh
#!/bin/sh
set -e

WAN4="$(nvram get wan_iface)"
WAN6="$(ip -6 route show default 2>/dev/null | awk '{print $5; exit}')"
[ -z "$WAN6" ] && WAN6="$(nvram get wan_iface)"
[ -z "$WAN6" ] && { logger -t kpb-fw "No WAN6 iface detected; skipping v6 hardening"; exit 0; }

LAN_IF="br0"
V4_SUBNET="10.17.13.0/24"

logger -t kpb-fw "Applying firewall. WAN4=$WAN4 WAN6=$WAN6 LAN=$LAN_IF"

# IPv4 cleanup of old ad-hoc rules
while iptables -D FORWARD -s 10.17.13.0/24 -j ACCEPT 2>/dev/null; do :; done
while iptables -t nat -D POSTROUTING -o wlan0 -j SNAT --to "$(nvram get lan_ipaddr)" 2>/dev/null; do :; done
while iptables -t nat -D POSTROUTING -s 10.17.13.0/24 -o vlan2 -j MASQUERADE 2>/dev/null; do :; done
while iptables -t nat -D POSTROUTING -s 10.17.13.0/24 -i br0 -o vlan2 -j SNAT --to-source "$(nvram get wan_ipaddr)" 2>/dev/null; do :; done
while iptables -t nat -D POSTROUTING -o br0 -s 10.17.13.0/24 -d 10.17.13.0/24 -j MASQUERADE 2>/dev/null; do :; done

# IPv4 forwarding/NAT for 10.17.13.0/24 -> WAN
iptables -C FORWARD -s "$V4_SUBNET" -o "$WAN4" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
iptables -I FORWARD 1 -s "$V4_SUBNET" -o "$WAN4" -m conntrack --ctstate NEW,ESTABLISHED,RELATED -j ACCEPT

iptables -C FORWARD -d "$V4_SUBNET" -i "$WAN4" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT 2>/dev/null || \
iptables -I FORWARD 2 -d "$V4_SUBNET" -i "$WAN4" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT

iptables -t nat -C POSTROUTING -s "$V4_SUBNET" -o "$WAN4" -j MASQUERADE 2>/dev/null || \
iptables -t nat -I POSTROUTING 1 -s "$V4_SUBNET" -o "$WAN4" -j MASQUERADE

# IPv6 hardened INPUT chain
ip6tables -N KPB_V6_INPUT 2>/dev/null || true
ip6tables -F KPB_V6_INPUT
ip6tables -C INPUT -j KPB_V6_INPUT 2>/dev/null || ip6tables -I INPUT 1 -j KPB_V6_INPUT

ip6tables -A KPB_V6_INPUT ! -i "$WAN6" -j RETURN
ip6tables -A KPB_V6_INPUT -i "$WAN6" -p udp --dport 51820 -j ACCEPT
ip6tables -A KPB_V6_INPUT -i "$WAN6" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip6tables -A KPB_V6_INPUT -i "$WAN6" -p udp --sport 547 --dport 546 -j ACCEPT
ip6tables -A KPB_V6_INPUT -i "$WAN6" -p ipv6-icmp --icmpv6-type destination-unreachable -j ACCEPT
ip6tables -A KPB_V6_INPUT -i "$WAN6" -p ipv6-icmp --icmpv6-type packet-too-big -j ACCEPT
ip6tables -A KPB_V6_INPUT -i "$WAN6" -p ipv6-icmp --icmpv6-type time-exceeded -j ACCEPT
ip6tables -A KPB_V6_INPUT -i "$WAN6" -p ipv6-icmp --icmpv6-type parameter-problem -j ACCEPT
ip6tables -A KPB_V6_INPUT -i "$WAN6" -m conntrack --ctstate NEW -j DROP
ip6tables -A KPB_V6_INPUT -j RETURN

# IPv6 hardened FORWARD chain
ip6tables -N KPB_V6_FWD 2>/dev/null || true
ip6tables -F KPB_V6_FWD
ip6tables -C FORWARD -j KPB_V6_FWD 2>/dev/null || ip6tables -I FORWARD 1 -j KPB_V6_FWD

ip6tables -A KPB_V6_FWD ! -i "$WAN6" -j RETURN
ip6tables -A KPB_V6_FWD -i "$WAN6" -m conntrack --ctstate ESTABLISHED,RELATED -j ACCEPT
ip6tables -A KPB_V6_FWD -i "$WAN6" -m conntrack --ctstate NEW -j DROP
ip6tables -A KPB_V6_FWD -j RETURN

logger -t kpb-fw "Firewall applied"
```

---

## What the firewall does

### `KPB_V6_INPUT` (router itself)

Processes packets destined **for the router** that arrive on the WAN interface:

| Rule | Effect |
|---|---|
| `! -i $WAN6 -j RETURN` | Immediately pass traffic not from WAN (LAN, loopback) |
| `-p udp --dport 51820 -j ACCEPT` | Allow inbound WireGuard |
| `--ctstate ESTABLISHED,RELATED -j ACCEPT` | Allow return traffic |
| `-p udp --sport 547 --dport 546 -j ACCEPT` | **Allow DHCPv6 replies from ISP** (critical — see below) |
| ICMPv6 types 1–4 | Allow error messages (unreachable, too-big, time-exceeded, param-problem) |
| `--ctstate NEW -j DROP` | Drop all other new inbound connections |
| `-j RETURN` | Fall through to default rules for anything else |

### `KPB_V6_FWD` (LAN devices)

Processes packets being **forwarded through the router** that arrive on WAN:

| Rule | Effect |
|---|---|
| `! -i $WAN6 -j RETURN` | Pass LAN→WAN traffic (br0 input) immediately |
| `--ctstate ESTABLISHED,RELATED -j ACCEPT` | Allow return traffic for LAN connections |
| `--ctstate NEW -j DROP` | Drop unsolicited new connections from internet to LAN |
| `-j RETURN` | Fall through for anything else |

**Note**: LAN→WAN forwarding is handled by DD-WRT's default rule  
`-A FORWARD -i br0 -m conntrack --ctstate NEW -j ACCEPT` which remains in place.

---

## Critical bug: DHCPv6 blocked by KPB_V6_INPUT

**Problem discovered 2026-05-16**: When `KPB_V6_INPUT` is inserted as the
first rule in INPUT, it intercepts DHCPv6 server replies before DD-WRT's
default DHCPv6 allow rule (`-p udp --sport 547 --dport 546 --ctstate NEW -j ACCEPT`).

The DHCPv6 server reply is a `NEW` connection (the client sends a SOLICIT on
UDP/546, the server replies from UDP/547 — this is not tracked as
ESTABLISHED/RELATED by conntrack). Without the explicit allow rule in
`KPB_V6_INPUT`, the reply is dropped, `dhcp6c` never gets a delegated prefix,
and IPv6 WAN is lost.

**Symptom**: `dhcp6c` starts normally but gets no delegated prefix. NVRAM
`ipv6_prefix` is empty. Router may restart `dhcp6c` in `-T LL` (link-local
only) mode.

**Fix**: The `-p udp --sport 547 --dport 546 -j ACCEPT` rule in `KPB_V6_INPUT`
must appear **before** the `--ctstate NEW -j DROP` rule.

---

## WAN interface detection

The script detects `$WAN6` dynamically:

```sh
WAN6="$(ip -6 route show default 2>/dev/null | awk '{print $5; exit}')"
[ -z "$WAN6" ] && WAN6="$(nvram get wan_iface)"
```

If no IPv6 default route exists yet when the script runs (e.g. `dhcp6c` hasn't
gotten a prefix yet), it falls back to the NVRAM `wan_iface` value (`vlan2`).
If that is also empty, the script exits cleanly with a log message rather than
applying broken rules.

**Known limitation**: If `$WAN6` resolves to something other than `vlan2`
(e.g. during a VLAN reconfiguration), rules will be applied to the wrong
interface. Verify with `ip6tables -S KPB_V6_INPUT` after applying — each rule
should show `-i vlan2`.

---

## IPv4 rules: isolated subnet (10.17.13.0/24)

The script also manages IPv4 forwarding and NAT for `10.17.13.0/24`, an
isolated IPv4-only subnet (no IPv6 delegation, no local DNS). This subnet
routes to WAN via `MASQUERADE`. Old ad-hoc rules accumulated over time are
cleaned up idempotently at the top of the script.

---

## Verifying the firewall is applied correctly

```sh
ssh root@10.17.12.1

# Check KPB_V6_INPUT — all WAN rules should show -i vlan2
ip6tables -S KPB_V6_INPUT

# Check KPB_V6_FWD
ip6tables -S KPB_V6_FWD

# Check DHCPv6 rule is present (critical)
ip6tables -S KPB_V6_INPUT | grep "547"

# Check INPUT chain ordering — KPB_V6_INPUT should be first
ip6tables -S INPUT | head -3

# Check packet counters (run after some traffic)
ip6tables -nvL FORWARD
```

---

## Re-applying after a reboot

The script is stored in `rc_firewall` NVRAM and runs automatically on boot.
To re-apply manually without rebooting:

```sh
ssh root@10.17.12.1 'nvram get rc_firewall | sh'
```

Or from DD-WRT web UI: **Administration → Commands → Run Firewall**.
