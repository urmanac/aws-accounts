# Architecture

This repository provides a secure workflow for managing AWS credentials using enforced **MFA (Multi-Factor Authentication)** and the **1Password CLI**.

## Overview

AWS access is configured so that long-lived IAM access keys cannot perform sensitive operations without an MFA session token. Instead of relying on permanent credentials, this workflow ensures all privileged actions are gated by MFA.

The process looks like this:

1. **Base Credentials**

   * Each account (e.g., `test`, `prod`) has a neutered IAM access key and secret key.
   * These keys are restricted: they cannot be used to perform sensitive actions until MFA has been satisfied.

2. **MFA Token Resolution via 1Password**

   * The MFA device ARN and corresponding OTP secret are stored securely in **1Password**.
   * The **1Password CLI (`op`)** is used to fetch the OTP code dynamically.
   * When you run the script, the `op` CLI prompts for biometric authentication (e.g., fingerprint).
   * This is **faster and smoother than typing codes manually**, and avoids copying sensitive secrets into plain files or shell history.

3. **STS Session Creation**

   * Once an OTP code is retrieved, the script exchanges the base IAM keys plus the OTP for an **AWS STS session token**.
   * The temporary session is exported to your environment and used by Terraform, AWS CLI, or SDK clients.
   * This session has full privileges, but only for a limited time.

4. **Environment Configuration**

   * Account-specific values (account number, MFA ARN, 1Password vault/item references) can be stored in `.env.test`, `.env.prod`, etc.
   * Users source the environment file, then run `get_mfa_session.sh` to authenticate seamlessly.

## Security Benefits

* **Mandatory MFA:** All AWS IAM activity requiring privilege elevation is protected by OTP.
* **No Shared Secrets in Files:** The actual OTP secret never touches disk; it remains secured in 1Password.
* **Biometric Gate:** Every MFA session requires biometric approval (fingerprint), raising the bar for compromise.
* **Short-Lived Sessions:** STS limits exposure by expiring credentials automatically.

## User Experience

* Running the script feels natural:

  * Set your profile with `export AWS_PROFILE=test-bootstrap` (or prod).
  * Run `source ./get_mfa_session.sh`.
  * Touch your fingerprint reader when prompted.
* Within seconds, you have a fully authorized session.

This workflow improves both **security** and **ergonomics**. It enforces AWS best practices without adding unnecessary friction to the developer experience.
