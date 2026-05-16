# DD-WRT WireGuard Server

## Purpose

The AWS bastion is public IPv6 only. It needs a WireGuard tunnel to obtain
IPv4 egress for package downloads and registry access. The home router acts as
the fallback WireGuard server when the university-hosted endpoint is offline.

## Router details

- Router OS: DD-WRT `r64764`
- Router model: Asus RT-AC88U
- WireGuard interface name in DD-WRT: `oet1`
- Router WireGuard public key: `OPNxgeBRyQ6jpyfhucAG4QVjUIS2llSEQOWh6xLhSmY=`
- Bastion WireGuard public key: `FSN4y6aRNuYT1uI40SkCloBvqS+jc6hZ1z0LPHVQVUA=`
- Router public IPv6 used as endpoint: `2601:245:c700:e:fe34:97ff:fe03:1ec0`
- Listen port: `51820/udp`
- Tunnel subnet: `10.66.66.0/24`

## DD-WRT UI configuration

Menu path: `Setup -> Tunnels -> WireGuard`

Tunnel settings:

- Tunnel: `Enable`
- Protocol Type: `WireGuard`
- CVE-2019-14899 Mitigation: enabled
- NAT via Tunnel: enabled
- Firewall Inbound: enabled
- Kill Switch: disabled
- Listen Port: `51820`
- MTU: `1420`
- Tunnel Address: `10.66.66.1/24`
- Tunnel label: `awsv4tun`

Peer settings:

- Peer Name: `bastion`
- Endpoint: disabled / blank
- Allowed IPs: `10.66.66.2/32`
- Route Allowed IPs via Tunnel: enabled
- Persistent Keepalive: `25`
- Peer Public Key: `FSN4y6aRNuYT1uI40SkCloBvqS+jc6hZ1z0LPHVQVUA=`

## Important UI pitfall

The top text box is only the tunnel label. It is not the tunnel IP field.

The working DD-WRT state uses:

- `oet1_label=awsv4tun`
- `oet1_ipaddr=10.66.66.1`
- `oet1_netmask=255.255.255.0`

If the address is entered in the label field by mistake, `oet1` comes up
without an IP and the tunnel handshakes but does not pass traffic.

## Bastion cutover

Live switch from the bastion to the home router endpoint:

```sh
sudo wg set wg0 peer gqrzji2A1YkREKl7bDsh+xk7fCuekTAGdLl8mNA+p1A= remove
sudo wg set wg0 peer OPNxgeBRyQ6jpyfhucAG4QVjUIS2llSEQOWh6xLhSmY= \
  endpoint [2601:245:c700:e:fe34:97ff:fe03:1ec0]:51820 \
  allowed-ips 0.0.0.0/1,128.0.0.0/1,10.66.66.0/24 \
  persistent-keepalive 25
sudo wg showconf wg0 | sudo tee /etc/wireguard/wg0.conf
```

Terraform / env values for the fallback endpoint:

```sh
MY_WIREGUARD_SERVER_PUB=OPNxgeBRyQ6jpyfhucAG4QVjUIS2llSEQOWh6xLhSmY=
MY_WIREGUARD_SERVER_IPV6=2601:245:c700:e:fe34:97ff:fe03:1ec0
```

## Validation results

Validated on 2026-05-16:

- `wg show oet1` on the router shows active handshakes from the bastion
- `curl -4 ifconfig.me` on the bastion returns `98.32.232.82`
- `ping 10.66.66.1` from the bastion succeeds (tunnel reachable)
- `ping 10.17.12.1` from the bastion succeeds (router LAN private IP reachable)
- `ping 4.208.26.196` from the bastion succeeds (public IPv4 internet reachable)
- Public IPv6 TCP/22 to the router times out from the bastion's public network (good)
- **No SSH key needed on the router** — network connectivity is all that's required

## Useful checks

Router side:

```sh
ssh root@10.17.12.1 'wg show oet1'
ssh root@10.17.12.1 'ip addr show oet1'
```

Bastion side:

```sh
ssh ec2-user@2a05:d018:106c:7801:ab08:3c88:efcd:f985 \
  'sudo wg show wg0; curl -4 --max-time 8 ifconfig.me'
```