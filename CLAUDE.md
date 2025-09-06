# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Common Commands

- **Apply Terraform (production)**: `make prod-apply`
- **Plan Terraform (production)**: `make prod-plan`
- **Apply Terraform (sandbox/test)**: `make apply-sb`
- **Plan Terraform (sandbox/test)**: `make plan-sb`
- **Import IAM user (sandbox)**: `make import-sb`
- **Import IAM user (production)**: `make import-prod`
- **Generate MFA session for production**: `make prod-sts`
- **Generate MFA session for sandbox**: `make sandbox-sts`

These targets invoke **OpenTofu** (`tofu`) with the appropriate `*.tfvars` and state files.

## High‑Level Architecture

- The repository implements a **secure MFA‑driven workflow** for AWS credential management. Base IAM access keys are neutered; privileged actions require a short‑lived STS token obtained after fetching a one‑time password from **1Password CLI** (`op`).
- `get_mfa_session.sh` sources environment‑specific files (e.g., `.env.test`, `.env.prod`) that contain the account ID, MFA device ARN, and 1Password vault reference. It then retrieves the OTP, calls `aws sts get-session-token`, and exports the temporary credentials.
- Terraform modules (`modules/bastion-ci`, `modules/bootstrap-admin`, `modules/vpc`) define the infrastructure. The **bastion‑ci** module provides an ephemeral bastion host for running Terraform/Tofu commands and managing IAM roles, designed to be free‑tier, on‑demand, and destroyable.
- The **bootstrap‑admin** module sets up admin IAM users; the **vpc** module defines VPC resources.
- The `Makefile` wraps common Terraform operations, using separate state and variable files for **prod** and **sandbox** environments.

## Additional Notes

- No explicit linting or test scripts are present in the repo. Developers should rely on Terraform validation (`tofu validate`) and manual review.
- No `.cursor` or Copilot rule files were found.
- The repository includes a `README.md` with usage snippets for setting `AWS_PROFILE` and sourcing the MFA script.

These details help Claude Code quickly understand how to build, apply, and manage the infrastructure safely.
