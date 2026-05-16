# DD-WRT Firewall Notes

## Scope

This documents the DD-WRT firewall changes needed for two things:

- safe IPv6 exposure with DHCPv6 prefix delegation enabled
- functional IPv4 forwarding for the WireGuard tunnel interface `oet1`

## IPv6 hardening

With DHCPv6-PD enabled, LAN devices receive globally routable IPv6 addresses in
`2601:245:c700:e::/64`. DD-WRT does not reliably block unsolicited inbound IPv6
connections on its own.

The saved `rc_firewall` script now creates:

- `KPB_V6_INPUT` to protect the router itself on the WAN IPv6 interface
- `KPB_V6_FWD` to block unsolicited new WAN->LAN forwarded IPv6 traffic

Allowed on WAN IPv6:

- `51820/udp` for WireGuard
- `ESTABLISHED,RELATED`
- essential ICMPv6 errors
- DHCPv6 replies: UDP source `547` to destination `546`

Everything else new on WAN IPv6 is dropped.

## Critical DHCPv6 rule

The explicit DHCPv6 allow rule is required:

```sh
ip6tables -A KPB_V6_INPUT -i "$WAN6" -p udp --sport 547 --dport 546 -j ACCEPT
```

Without it, `KPB_V6_INPUT` intercepts DHCPv6 replies before DD-WRT's default
allow rule and IPv6 prefix delegation breaks.

Observed failure mode:

- `dhcp6c` falls back to link-local only behavior
- `ipv6_prefix` is empty
- WAN IPv6 disappears even though the interface remains up

## WireGuard IPv4 rules

The WireGuard server on `oet1` needed three additional IPv4 rules to work as a
general egress path for the bastion:

```sh
iptables -C INPUT -i oet1 -j ACCEPT 2>/dev/null || iptables -I INPUT 1 -i oet1 -j ACCEPT
iptables -C FORWARD -i oet1 -o vlan2 -j ACCEPT 2>/dev/null || iptables -I FORWARD 1 -i oet1 -o vlan2 -j ACCEPT
iptables -C FORWARD -i vlan2 -o oet1 -m state --state RELATED,ESTABLISHED -j ACCEPT 2>/dev/null || iptables -I FORWARD 2 -i vlan2 -o oet1 -m state --state RELATED,ESTABLISHED -j ACCEPT
```

Why they are needed:

- `INPUT`: allows the router itself to answer tunnel traffic arriving on `oet1`
- `FORWARD oet1 -> vlan2`: allows bastion IPv4 traffic to leave via WAN
- `FORWARD vlan2 -> oet1`: allows return traffic back into the tunnel

These rules were appended to the saved DD-WRT `rc_firewall` script on
2026-05-16 so the behavior survives reboot.

## Validation

Validated after applying the rules:

- `ping 10.66.66.1` from the bastion succeeds
- `curl -4 ifconfig.me` from the bastion returns `98.32.232.82`
- public IPv6 TCP/22 to the router times out
- the WireGuard handshake remains active while SSH over public IPv6 stays shut