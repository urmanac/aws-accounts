#!/bin/bash
# Dynamic MFA session script - no hardcoded account numbers
# bash/zsh compatible

aws_mfa() {
  set -euo pipefail

  if [[ -z "${AWS_PROFILE:-}" ]]; then
      echo "Error: AWS_PROFILE must be set" >&2
      return 1
  fi

  ENV=$(echo "$AWS_PROFILE" | cut -d'-' -f1)
  ENV_FILE=".env.${ENV}"

  if [[ ! -f "$ENV_FILE" ]]; then
      echo "Error: Environment file $ENV_FILE not found" >&2
      echo "Expected: ACCOUNT_ID, MFA_DEVICE_NAME, OP_VAULT_ITEM" >&2
      return 1
  fi

  # shellcheck disable=SC1090
  source "$ENV_FILE"

  if [[ -z "${ACCOUNT_ID:-}" || -z "${MFA_DEVICE_NAME:-}" || -z "${OP_VAULT_ITEM:-}" ]]; then
      echo "Error: Missing required variables in $ENV_FILE" >&2
      return 1
  fi

  echo "Getting MFA token for $ENV (account ${ACCOUNT_ID})..."

  MFA_CODE=$(op read "$OP_VAULT_ITEM") || return 1

  CREDS=$(aws sts get-session-token \
    --serial-number "arn:aws:iam::${ACCOUNT_ID}:mfa/${MFA_DEVICE_NAME}" \
    --token-code "$MFA_CODE" \
    --duration-seconds 3600) || return 1

  export AWS_ACCESS_KEY_ID=$(echo "$CREDS" | jq -r .Credentials.AccessKeyId)
  export AWS_SECRET_ACCESS_KEY=$(echo "$CREDS" | jq -r .Credentials.SecretAccessKey)
  export AWS_SESSION_TOKEN=$(echo "$CREDS" | jq -r .Credentials.SessionToken)

  echo "✓ MFA session active for $ENV (expires in 1 hour)"
}
