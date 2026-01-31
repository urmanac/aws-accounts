#!/bin/bash
# =============================================================================
# Sunkworks Plan B Authentication - Backup Methods When Primary Fails
# =============================================================================
# The "plan B" every Sunkworks episode needs - multiple fallback auth methods.
# =============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# Authentication Priority Order
# -----------------------------------------------------------------------------
# 1. YubiKey TOTP (fastest, no typing)
# 2. 1Password TOTP (biometric)
# 3. AWS SSO (browser-based)
# 4. Manual TOTP entry (last resort)
# 5. Emergency break-glass IAM credentials

sunkworks_authenticate() {
    local env="${1:-}"
    local force_method="${2:-}"
    
    if [ -z "$env" ]; then
        if [ -n "${AWS_PROFILE:-}" ]; then
            env="$(printf '%s' "$AWS_PROFILE" | cut -d'-' -f1)"
        else
            echo -e "${RED}Error: Specify environment${NC}" >&2
            return 1
        fi
    fi
    
    echo -e "${BLUE}🔐 Sunkworks Authentication for: ${env}${NC}"
    
    local methods=()
    
    if [ -n "$force_method" ]; then
        methods=("$force_method")
    else
        # Build priority list based on availability
        
        # 1. YubiKey
        if command -v ykman &> /dev/null && ykman list 2>/dev/null | grep -q "YubiKey"; then
            methods+=("yubikey")
        fi
        
        # 2. 1Password
        if command -v op &> /dev/null; then
            methods+=("1password")
        fi
        
        # 3. AWS SSO
        if [ -n "${SSO_START_URL:-}" ]; then
            methods+=("sso")
        fi
        
        # 4. Manual (always available)
        methods+=("manual")
    fi
    
    echo -e "${BLUE}  Available methods: ${methods[*]}${NC}"
    
    local success=false
    
    for method in "${methods[@]}"; do
        echo -e "${YELLOW}Trying: ${method}${NC}"
        
        case "$method" in
            yubikey)
                if sunkworks_try_yubikey "$env"; then
                    success=true
                    break
                fi
                ;;
            1password)
                if sunkworks_try_1password "$env"; then
                    success=true
                    break
                fi
                ;;
            sso)
                if sunkworks_try_sso "$env"; then
                    success=true
                    break
                fi
                ;;
            manual)
                if sunkworks_try_manual "$env"; then
                    success=true
                    break
                fi
                ;;
            breakglass)
                if sunkworks_try_breakglass "$env"; then
                    success=true
                    break
                fi
                ;;
            *)
                echo -e "${YELLOW}Unknown method: ${method}${NC}"
                ;;
        esac
        
        echo -e "${YELLOW}  ${method} failed, trying next...${NC}"
    done
    
    if [ "$success" = true ]; then
        echo -e "${GREEN}✓ Authentication successful${NC}"
        return 0
    else
        echo -e "${RED}❌ All authentication methods failed${NC}" >&2
        echo -e "${YELLOW}Try: sunkworks_authenticate $env breakglass${NC}" >&2
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Individual Method Implementations
# -----------------------------------------------------------------------------

sunkworks_try_yubikey() {
    local env="$1"
    local cred="${YUBIKEY_CREDENTIAL:-aws-${env}}"
    
    if ! ykman oath accounts list 2>/dev/null | grep -q "$cred"; then
        echo -e "${YELLOW}  YubiKey credential not found: ${cred}${NC}" >&2
        return 1
    fi
    
    echo -e "${YELLOW}  🔐 Touch YubiKey...${NC}"
    
    local code
    code=$(ykman oath accounts code "$cred" 2>/dev/null | awk '{print $NF}')
    
    if [ -z "$code" ]; then
        return 1
    fi
    
    sunkworks_get_session "$env" "$code"
}

sunkworks_try_1password() {
    local env="$1"
    local env_file="${SCRIPT_DIR}/../.env.${env}"
    
    if [ ! -f "$env_file" ]; then
        return 1
    fi
    
    # shellcheck disable=SC1090
    source "$env_file"
    
    if [ -z "${OP_VAULT_ITEM:-}" ]; then
        return 1
    fi
    
    # Check/refresh 1Password session
    if ! op whoami &>/dev/null; then
        echo -e "${YELLOW}  Signing into 1Password...${NC}"
        eval "$(op signin)" || return 1
    fi
    
    local code
    code=$(op read "$OP_VAULT_ITEM" 2>/dev/null)
    
    if [ -z "$code" ]; then
        return 1
    fi
    
    sunkworks_get_session "$env" "$code"
}

sunkworks_try_sso() {
    local env="$1"
    local profile="sunkworks-${env}"
    
    # Source SSO script if available
    if [ -f "${SCRIPT_DIR}/sunkworks-sso.sh" ]; then
        # shellcheck disable=SC1091
        source "${SCRIPT_DIR}/sunkworks-sso.sh"
    fi
    
    # Try SSO login
    aws sso login --profile "$profile" 2>/dev/null || return 1
    
    # Verify it worked
    if aws sts get-caller-identity --profile "$profile" &>/dev/null; then
        export AWS_PROFILE="$profile"
        return 0
    fi
    
    return 1
}

sunkworks_try_manual() {
    local env="$1"
    
    echo -e "${YELLOW}  Enter MFA code manually: ${NC}"
    read -r code
    
    if [ -z "$code" ]; then
        return 1
    fi
    
    sunkworks_get_session "$env" "$code"
}

sunkworks_try_breakglass() {
    local env="$1"
    
    echo -e "${RED}⚠️  BREAK-GLASS ACCESS${NC}"
    echo -e "${YELLOW}This should only be used in emergencies!${NC}"
    echo ""
    
    local breakglass_file="${SCRIPT_DIR}/../.breakglass.${env}"
    
    if [ ! -f "$breakglass_file" ]; then
        echo -e "${RED}Break-glass credentials not found: ${breakglass_file}${NC}" >&2
        echo ""
        echo "To set up break-glass access, create $breakglass_file with:"
        echo "  AWS_ACCESS_KEY_ID=AKIA..."
        echo "  AWS_SECRET_ACCESS_KEY=..."
        echo ""
        echo "⚠️  Store this file securely and rotate credentials regularly!"
        return 1
    fi
    
    # Confirm action
    echo -e "${YELLOW}Type 'BREAKGLASS' to confirm emergency access:${NC}"
    read -r confirm
    
    if [ "$confirm" != "BREAKGLASS" ]; then
        echo "Cancelled."
        return 1
    fi
    
    # shellcheck disable=SC1090
    source "$breakglass_file"
    
    # Verify credentials work
    if aws sts get-caller-identity &>/dev/null; then
        echo -e "${GREEN}✓ Break-glass credentials loaded${NC}"
        echo -e "${RED}⚠️  Remember to rotate these credentials after use!${NC}"
        return 0
    else
        echo -e "${RED}Break-glass credentials invalid${NC}" >&2
        return 1
    fi
}

# -----------------------------------------------------------------------------
# Helper: Get STS Session Token
# -----------------------------------------------------------------------------

sunkworks_get_session() {
    local env="$1"
    local code="$2"
    local duration="${SESSION_DURATION:-3600}"
    
    local env_file="${SCRIPT_DIR}/../.env.${env}"
    
    if [ ! -f "$env_file" ]; then
        echo -e "${RED}Environment file not found: ${env_file}${NC}" >&2
        return 1
    fi
    
    # shellcheck disable=SC1090
    source "$env_file"
    
    if [ -z "${ACCOUNT_ID:-}" ] || [ -z "${MFA_DEVICE_NAME:-}" ]; then
        echo -e "${RED}ACCOUNT_ID and MFA_DEVICE_NAME required in ${env_file}${NC}" >&2
        return 1
    fi
    
    local mfa_arn="arn:aws:iam::${ACCOUNT_ID}:mfa/${MFA_DEVICE_NAME}"
    
    export AWS_PAGER=""
    
    local creds
    creds=$(aws sts get-session-token \
        --serial-number "$mfa_arn" \
        --token-code "$code" \
        --duration-seconds "$duration" 2>&1)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}  STS error: ${creds}${NC}" >&2
        return 1
    fi
    
    export AWS_ACCESS_KEY_ID=$(echo "$creds" | jq -r .Credentials.AccessKeyId)
    export AWS_SECRET_ACCESS_KEY=$(echo "$creds" | jq -r .Credentials.SecretAccessKey)
    export AWS_SESSION_TOKEN=$(echo "$creds" | jq -r .Credentials.SessionToken)
    export SUNKWORKS_SESSION_EXPIRES=$(echo "$creds" | jq -r .Credentials.Expiration)
    export SUNKWORKS_SESSION_ENV="$env"
    
    return 0
}

# -----------------------------------------------------------------------------
# Quick Access Aliases
# -----------------------------------------------------------------------------

sunkworks_quick_sb() {
    sunkworks_authenticate "sb"
}

sunkworks_quick_prod() {
    sunkworks_authenticate "prod"
}

# -----------------------------------------------------------------------------
# Pre-stream Check
# -----------------------------------------------------------------------------

sunkworks_prestream_check() {
    echo -e "${BLUE}🎬 Sunkworks Pre-Stream Authentication Check${NC}"
    echo ""
    
    local all_ok=true
    
    # Check YubiKey
    echo -n "YubiKey: "
    if command -v ykman &> /dev/null && ykman list 2>/dev/null | grep -q "YubiKey"; then
        echo -e "${GREEN}✓ Connected${NC}"
        echo -n "  OATH credentials: "
        local creds=$(ykman oath accounts list 2>/dev/null | grep -c "aws" || echo "0")
        if [ "$creds" -gt 0 ]; then
            echo -e "${GREEN}$creds found${NC}"
        else
            echo -e "${YELLOW}None with 'aws' prefix${NC}"
        fi
    else
        echo -e "${YELLOW}Not detected${NC}"
    fi
    
    # Check 1Password
    echo -n "1Password: "
    if command -v op &> /dev/null; then
        if op whoami &>/dev/null; then
            echo -e "${GREEN}✓ Signed in${NC}"
        else
            echo -e "${YELLOW}Installed but not signed in${NC}"
        fi
    else
        echo -e "${YELLOW}Not installed${NC}"
    fi
    
    # Check AWS CLI
    echo -n "AWS CLI: "
    if command -v aws &> /dev/null; then
        echo -e "${GREEN}✓ Installed ($(aws --version | cut -d' ' -f1))${NC}"
    else
        echo -e "${RED}Not installed${NC}"
        all_ok=false
    fi
    
    # Check SSO configuration
    echo -n "SSO Config: "
    if [ -n "${SSO_START_URL:-}" ]; then
        echo -e "${GREEN}✓ Configured${NC}"
    else
        echo -e "${YELLOW}Not configured${NC}"
    fi
    
    # Check environment files
    echo ""
    echo "Environment files:"
    for env in sb prod; do
        local env_file="${SCRIPT_DIR}/../.env.${env}"
        echo -n "  .env.${env}: "
        if [ -f "$env_file" ]; then
            echo -e "${GREEN}✓ Found${NC}"
        else
            echo -e "${YELLOW}Not found${NC}"
        fi
    done
    
    echo ""
    if [ "$all_ok" = true ]; then
        echo -e "${GREEN}✓ Ready for streaming!${NC}"
    else
        echo -e "${YELLOW}⚠️  Some checks failed - review above${NC}"
    fi
}

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------

sunkworks_planb_help() {
    echo -e "${BLUE}Sunkworks Plan B Authentication${NC}"
    echo ""
    echo "Commands:"
    echo "  sunkworks_authenticate [env] [method]  - Auto-try auth methods"
    echo "  sunkworks_quick_sb                      - Quick sandbox access"
    echo "  sunkworks_quick_prod                    - Quick prod access"
    echo "  sunkworks_prestream_check               - Verify auth setup"
    echo ""
    echo "Methods (in priority order):"
    echo "  yubikey   - Hardware TOTP (fastest)"
    echo "  1password - 1Password CLI with biometric"
    echo "  sso       - AWS SSO browser login"
    echo "  manual    - Type TOTP code"
    echo "  breakglass - Emergency IAM credentials"
    echo ""
    echo "Examples:"
    echo "  sunkworks_authenticate sb"
    echo "  sunkworks_authenticate prod yubikey"
    echo "  sunkworks_authenticate sb breakglass"
}

# Export functions
export -f sunkworks_authenticate
export -f sunkworks_try_yubikey
export -f sunkworks_try_1password
export -f sunkworks_try_sso
export -f sunkworks_try_manual
export -f sunkworks_try_breakglass
export -f sunkworks_get_session
export -f sunkworks_quick_sb
export -f sunkworks_quick_prod
export -f sunkworks_prestream_check
export -f sunkworks_planb_help
