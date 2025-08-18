#!/bin/bash
# Dynamic MFA session script - no hardcoded account numbers
# bash/zsh compatible
# Safe to source in zsh or bash
# Usage: aws_mfa

aws_mfa() {
  # Wrapper that **never returns non-zero** (avoids killing shells with ERR_EXIT)
  _aws_mfa_impl "$@" && return 0

  # If we got here, the impl failed; print a friendly message and do not return non-zero
  local code=$?
  echo "aws_mfa: failed (status $code). Shell left untouched." >&2
  return 0
}

_aws_mfa_impl() {
  # Localize shell options in zsh so we don't leak anything
  if [ -n "${ZSH_VERSION:-}" ]; then
    emulate -L zsh
    setopt localoptions pipefail
    unsetopt errexit              # don't let zsh auto-exit inside this function
    setopt nounset                # like set -u
  else
    # bash: avoid -e entirely; we’ll check statuses manually
    set +e
    set -u
    # pipefail only if supported
    (set -o pipefail) 2>/dev/null && set -o pipefail
  fi

  # ---- Preconditions & inputs ----
  if [ -z "${AWS_PROFILE:-}" ]; then
    echo "Error: AWS_PROFILE must be set (e.g., sb-bootstrap)" >&2
    return 1
  fi

  local ENV="$(printf '%s' "$AWS_PROFILE" | cut -d'-' -f1)"

  local ENV_FILE=".env.${ENV}"

  if [ ! -f "$ENV_FILE" ]; then
    cat >&2 <<EOF
Error: Environment file $ENV_FILE not found.
Create it with:
  ACCOUNT_ID=your-account-id
  MFA_DEVICE_NAME=your-mfa-device-name
  OP_VAULT_ITEM=op://Vault/Item/one-time password?attribute=otp
EOF
    return 1
  fi

  # shellcheck disable=SC1090
  source "$ENV_FILE" || { echo "Error: couldn't source $ENV_FILE" >&2; return 1; }

  for var in ACCOUNT_ID MFA_DEVICE_NAME OP_VAULT_ITEM; do
    eval val=\$$var
    if [ -z "${val:-}" ]; then
      echo "Error: $var is missing in $ENV_FILE" >&2
      return 1
    fi
  done

  # ---- Commands that might fail ----
  export AWS_PAGER=""

  # 1Password OTP
  local MFA_CODE
  MFA_CODE="$(op read "$OP_VAULT_ITEM")" || {
    echo "Error: failed to read OTP from 1Password ($OP_VAULT_ITEM)" >&2
    return 1
  }

  # STS get-session-token
  local CREDS
  CREDS="$(aws sts get-session-token \
            --serial-number "arn:aws:iam::${ACCOUNT_ID}:mfa/${MFA_DEVICE_NAME}" \
            --token-code "$MFA_CODE" \
            --duration-seconds 3600 2>&1)"
  if [ $? -ne 0 ]; then
    echo "Error: aws sts get-session-token failed:" >&2
    echo "$CREDS" >&2
    return 1
  fi

  # ---- Parse & export ----
  # Use printf to avoid issues with echo + backslash escapes
  export AWS_ACCESS_KEY_ID="$(printf '%s' "$CREDS" | jq -r .Credentials.AccessKeyId)" || return 1
  export AWS_SECRET_ACCESS_KEY="$(printf '%s' "$CREDS" | jq -r .Credentials.SecretAccessKey)" || return 1
  export AWS_SESSION_TOKEN="$(printf '%s' "$CREDS" | jq -r .Credentials.SessionToken)" || return 1

  printf '✓ MFA session active for %s (account %s). Expires in 1 hour.\n' "$ENV" "$ACCOUNT_ID"
  return 0
}
