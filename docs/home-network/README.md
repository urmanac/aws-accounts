# Home Network

This directory documents the non-AWS infrastructure that the AWS account
depends on: the home DD-WRT router, its IPv6 firewalling, and the WireGuard
path that provides IPv4 egress for the IPv6-only bastion.

## Current validated state

Validated on 2026-05-16:

- DD-WRT router: Asus RT-AC88U, firmware `r64764` (2026-05-08)
- WAN IPv4: `98.32.232.82`
- WAN IPv6 prefix delegation: `2601:245:c700:e::/64`
- WireGuard server interface: `oet1`
- WireGuard listen port: `51820/udp`
- WireGuard tunnel subnet: `10.66.66.0/24`
- Router tunnel IP: `10.66.66.1/24`
- Bastion tunnel IP: `10.66.66.2/32`

Validated behaviors:

- Bastion WireGuard handshake to the home router is active
- Bastion IPv4 egress exits via the home WAN IPv4 (`98.32.232.82`)
- Bastion can reach public IPv4 internet through the tunnel (ghcr.io reachable)
- Router private LAN IP (`10.17.12.1`) is reachable from the bastion
- Other private subnets (10.17.13.0/24, etc.) are not reachable — network isolation working
- Router public IPv6 TCP/22 is not reachable from the public internet
- No SSH access to the router is required — network connectivity is the only test

## Files

- `dd-wrt-wireguard.md`: DD-WRT WireGuard server configuration, bastion switch,
  and validation results
- `dd-wrt-firewall.md`: IPv6 hardening and the additional IPv4 rules needed for
  WireGuard traffic on DD-WRT