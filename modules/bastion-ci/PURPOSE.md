# PURPOSE.md

## Purpose

This document describes the purpose of the temporary **Terraform Bastion Host** and supporting infrastructure in our AWS accounts.

The guiding principle of this setup is **diamond-perfect computing** — reproducible, ephemeral, and cost-minimal infrastructure that derives its value from code, not from retained cloud state.

## Context

* We are currently operating with **two AWS accounts**: one for **prod**, one for **test**.
* We are **not yet in an AWS Organization**, and will not duplicate features of Organizations (e.g. Identity Center, SCPs) prematurely.
* All data we work with in cloud is **disposable / replaceable / of zero inherent value**. Persistent state is sourced from Git and the home lab.
* We are pursuing a **"zero-paid" cloud strategy** — leveraging only free-tier services where possible.
* Our infrastructure must scale down to zero gracefully, while preserving the ability to scale up in the future.

## Terraform Bastion

The bastion serves as a lightweight, ephemeral environment to:

1. Run **Terraform (or OpenTofu)** against AWS accounts.
2. Manage IAM roles (especially **IAM Roles Anywhere** for future GitLab Runner integrations).
3. Provide a controlled entry point for bootstrapping infra in a way that is:

   * Ephemeral
   * Auditable
   * Destroyable without consequence

### Constraints

* Must fit in the **free tier** (e.g. `t4g.micro` or `t4g.small` Graviton instances).
* Must be **started on-demand** and **torn down after use**. No permanent compute.
* Must not introduce persistent cloud-side dependencies beyond what will exist in the Organization model.
* Must be a **training wheel** — eventually replaced by GitLab Runners or other CI agents running via IAM Roles Anywhere.

### Future Considerations

* Bastion may be automated with **ASG or scheduled startup/shutdown** for just-in-time provisioning.
* When we adopt an **Organization + Identity Center**, the bastion will be retired.
* Persistent state will always come from Git and home lab, never from this bastion.

## Philosophy

* **Replication with one node**: Build scaffolding that represents scalability, but only run the bare minimum.
* **Ephemerality**: Tear down and rebuild everything from Git. No snowflakes.
* **Free-first**: Never pay for what is not necessary.
* **Identity over infrastructure**: Long-term trust and structure come from IAM and Org features, not from keeping machines alive.

This bastion is not the foundation of our infrastructure — it is the **ladder we will kick away**.
