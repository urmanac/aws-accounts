# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

### Standard Operations
- **Apply Terraform (production)**: `make prod-apply`
- **Plan Terraform (production)**: `make prod-plan`
- **Apply Terraform (sandbox/test)**: `make apply-sb`
- **Plan Terraform (sandbox/test)**: `make plan-sb`
- **Import IAM user (sandbox)**: `make import-sb`
- **Import IAM user (production)**: `make import-prod`
- **Generate MFA session for production**: `make prod-sts`
- **Generate MFA session for sandbox**: `make sandbox-sts`

These targets invoke **OpenTofu** (`tofu`) with the appropriate `*.tfvars` and state files.

### Bastion Operations

The bastion is a single EC2 instance (not in an ASG) with a fixed private ENI at
`10.10.1.100`. It can be destroyed and recreated without touching VPC, subnets,
or IAM resources:

```bash
# Destroy bastion only
tofu destroy -var-file=sb.tfvars -state=sb.tfstate -target='module.bastion_ci'

# Recreate bastion
tofu apply -var-file=sb.tfvars -state=sb.tfstate -target='module.bastion_ci'
```

The new bastion will get a new IPv6 address. Update any SSH configs or scripts
that reference the old address.

## High‑Level Architecture

- The repository implements a **secure MFA‑driven workflow** for AWS credential management. Base IAM access keys are neutered; privileged actions require a short‑lived STS token obtained after fetching a one‑time password from **1Password CLI** (`op`).
- `get_mfa_session.sh` sources environment‑specific files (e.g., `.env.sb`, `.env.prod`) that contain the account ID, MFA device ARN, and 1Password vault reference. It then retrieves the OTP, calls `aws sts get-session-token`, and exports the temporary credentials.
- Terraform modules (`modules/bastion-ci`, `modules/bootstrap-admin`, `modules/vpc`) define the infrastructure. The **bastion‑ci** module provides an ephemeral bastion host for running Terraform/Tofu commands and managing IAM roles, designed to be free‑tier, on‑demand, and destroyable.
- The **bootstrap‑admin** module sets up admin IAM users; the **vpc** module defines VPC resources.
- The `Makefile` wraps common Terraform operations, using separate state and variable files for **prod** and **sandbox** environments.

### WireGuard for IPv4 Egress

The bastion is **IPv6-only** (no public IPv4). It obtains IPv4 egress through a
WireGuard tunnel configured at boot time using variables from `.env`:

| Variable | Purpose |
|---|---|
| `MY_WIREGUARD_SERVER_PUB` | WireGuard server public key |
| `MY_WIREGUARD_SERVER_IPV6` | WireGuard server IPv6 endpoint address |
| `MY_WIREGUARD_CLIENT_KEY` | Bastion WireGuard private key |
| `MY_WIREGUARD_CLIENT_PUB` | Bastion WireGuard public key (peer on server) |

Two endpoint configurations are maintained as separate files:

- **`.env`** — primary endpoint (RIT CSH-hosted, ~160ms latency, active Sept–May)
- **`.env.summer`** — fallback endpoint (home DD-WRT router, ~210ms, used June–Aug)

Both are in `.gitignore` (they contain private WireGuard keys). To swap
endpoints for summer when the RIT server goes offline:

```bash
mv .env .env.rit && mv .env.summer .env
# then rebuild bastion to bake in the new endpoint:
tofu apply -var-file=sb.tfvars -state=sb.tfstate -target='module.bastion_ci'
```

See `docs/wireguard-ddwrt-fallback.md` for full details including live switching
(without a rebuild) and `docs/home-network/` for DD-WRT configuration.

## Additional Notes

- No explicit linting or test scripts are present in the repo. Developers should rely on Terraform validation (`tofu validate`) and manual review.
- The repository includes a `README.md` with usage snippets for setting `AWS_PROFILE` and sourcing the MFA script.
- Home network infrastructure (DD-WRT router, IPv6 firewall, WireGuard server) is documented in `docs/home-network/`.

These details help Claude Code quickly understand how to build, apply, and manage the infrastructure safely.
