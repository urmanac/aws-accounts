#!/bin/bash
# =============================================================================
# Sunkworks Enhanced MFA - YubiKey Integration
# =============================================================================
# Hardware MFA for live streaming - no more typing TOTP codes on camera.
# Supports YubiKey 5 series with both TOTP and FIDO2/WebAuthn.
# =============================================================================

set -euo pipefail

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Script location for sourcing env files
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Default settings
MFA_METHOD="${MFA_METHOD:-auto}"  # auto, yubikey, 1password, manual
SESSION_DURATION="${SESSION_DURATION:-3600}"  # 1 hour default
REFRESH_THRESHOLD="${REFRESH_THRESHOLD:-300}"  # Refresh when 5 min left

# -----------------------------------------------------------------------------
# YubiKey Functions
# -----------------------------------------------------------------------------

sunkworks_detect_yubikey() {
    # Check if YubiKey is present
    if command -v ykman &> /dev/null; then
        if ykman list 2>/dev/null | grep -q "YubiKey"; then
            echo "yubikey"
            return 0
        fi
    fi
    
    # Check for YubiKey via ykinfo
    if command -v ykinfo &> /dev/null; then
        if ykinfo -q 2>/dev/null; then
            echo "yubikey"
            return 0
        fi
    fi
    
    echo "none"
    return 1
}

sunkworks_get_yubikey_totp() {
    local credential="$1"
    
    if ! command -v ykman &> /dev/null; then
        echo -e "${RED}Error: ykman not installed. Install with: brew install ykman${NC}" >&2
        return 1
    fi
    
    echo -e "${YELLOW}🔐 Touch YubiKey to generate TOTP...${NC}" >&2
    
    # This will prompt for touch
    local code
    code=$(ykman oath accounts code "$credential" 2>/dev/null | awk '{print $NF}')
    
    if [ -z "$code" ]; then
        echo -e "${RED}Error: Failed to get TOTP from YubiKey${NC}" >&2
        return 1
    fi
    
    echo "$code"
}

sunkworks_list_yubikey_credentials() {
    if command -v ykman &> /dev/null; then
        echo -e "${BLUE}Available OATH credentials on YubiKey:${NC}" >&2
        ykman oath accounts list 2>/dev/null
    fi
}

# -----------------------------------------------------------------------------
# 1Password Functions
# -----------------------------------------------------------------------------

sunkworks_get_1password_totp() {
    local vault_item="$1"
    
    if ! command -v op &> /dev/null; then
        echo -e "${RED}Error: 1Password CLI not installed${NC}" >&2
        return 1
    fi
    
    # Check if signed in
    if ! op whoami &>/dev/null; then
        echo -e "${YELLOW}🔓 Signing into 1Password...${NC}" >&2
        eval "$(op signin)" || {
            echo -e "${RED}Error: 1Password signin failed${NC}" >&2
            return 1
        }
    fi
    
    local code
    code=$(op read "$vault_item" 2>/dev/null)
    
    if [ -z "$code" ]; then
        echo -e "${RED}Error: Failed to read TOTP from 1Password${NC}" >&2
        return 1
    fi
    
    echo "$code"
}

# -----------------------------------------------------------------------------
# Auto-detect MFA Method
# -----------------------------------------------------------------------------

sunkworks_detect_mfa_method() {
    local env="$1"
    local env_file="${SCRIPT_DIR}/../.env.${env}"
    
    # Check if YubiKey is available and has credentials
    if [ "$(sunkworks_detect_yubikey)" = "yubikey" ]; then
        # Check if there's a matching credential
        local yubikey_cred="${YUBIKEY_CREDENTIAL:-aws-${env}}"
        if ykman oath accounts list 2>/dev/null | grep -q "$yubikey_cred"; then
            echo "yubikey"
            return 0
        fi
    fi
    
    # Check if 1Password is configured
    if [ -f "$env_file" ]; then
        # shellcheck disable=SC1090
        source "$env_file"
        if [ -n "${OP_VAULT_ITEM:-}" ]; then
            echo "1password"
            return 0
        fi
    fi
    
    # Fall back to manual
    echo "manual"
}

# -----------------------------------------------------------------------------
# Get MFA Code (unified interface)
# -----------------------------------------------------------------------------

sunkworks_get_mfa_code() {
    local method="$1"
    local env="$2"
    
    case "$method" in
        yubikey)
            local cred="${YUBIKEY_CREDENTIAL:-aws-${env}}"
            sunkworks_get_yubikey_totp "$cred"
            ;;
        1password)
            local env_file="${SCRIPT_DIR}/../.env.${env}"
            if [ -f "$env_file" ]; then
                # shellcheck disable=SC1090
                source "$env_file"
                sunkworks_get_1password_totp "$OP_VAULT_ITEM"
            else
                echo -e "${RED}Error: .env.${env} not found${NC}" >&2
                return 1
            fi
            ;;
        manual)
            echo -e "${YELLOW}Enter MFA code: ${NC}" >&2
            read -r code
            echo "$code"
            ;;
        *)
            echo -e "${RED}Unknown MFA method: ${method}${NC}" >&2
            return 1
            ;;
    esac
}

# -----------------------------------------------------------------------------
# Main MFA Session Function (Sunkworks version)
# -----------------------------------------------------------------------------

sunkworks_mfa() {
    local env="${1:-}"
    
    # Determine environment
    if [ -z "$env" ]; then
        if [ -n "${AWS_PROFILE:-}" ]; then
            env="$(printf '%s' "$AWS_PROFILE" | cut -d'-' -f1)"
        else
            echo -e "${RED}Error: Specify environment or set AWS_PROFILE${NC}" >&2
            echo "Usage: sunkworks_mfa <env>" >&2
            echo "       AWS_PROFILE=sb-bootstrap sunkworks_mfa" >&2
            return 1
        fi
    fi
    
    local env_file="${SCRIPT_DIR}/../.env.${env}"
    
    if [ ! -f "$env_file" ]; then
        echo -e "${RED}Error: $env_file not found${NC}" >&2
        return 1
    fi
    
    # Source environment
    # shellcheck disable=SC1090
    source "$env_file"
    
    # Validate required variables
    if [ -z "${ACCOUNT_ID:-}" ]; then
        echo -e "${RED}Error: ACCOUNT_ID not set in $env_file${NC}" >&2
        return 1
    fi
    
    if [ -z "${MFA_DEVICE_NAME:-}" ]; then
        echo -e "${RED}Error: MFA_DEVICE_NAME not set in $env_file${NC}" >&2
        return 1
    fi
    
    # Detect MFA method
    local method
    if [ "$MFA_METHOD" = "auto" ]; then
        method=$(sunkworks_detect_mfa_method "$env")
        echo -e "${BLUE}Auto-detected MFA method: ${method}${NC}"
    else
        method="$MFA_METHOD"
    fi
    
    # Get MFA code
    local mfa_code
    mfa_code=$(sunkworks_get_mfa_code "$method" "$env")
    
    if [ -z "$mfa_code" ]; then
        echo -e "${RED}Error: Failed to get MFA code${NC}" >&2
        return 1
    fi
    
    # Disable pager for AWS CLI
    export AWS_PAGER=""
    
    # Build MFA ARN
    local mfa_arn="arn:aws:iam::${ACCOUNT_ID}:mfa/${MFA_DEVICE_NAME}"
    
    echo -e "${BLUE}🔑 Getting session token...${NC}"
    
    # Get session token
    local creds
    creds=$(aws sts get-session-token \
        --serial-number "$mfa_arn" \
        --token-code "$mfa_code" \
        --duration-seconds "$SESSION_DURATION" 2>&1)
    
    if [ $? -ne 0 ]; then
        echo -e "${RED}Error: STS get-session-token failed:${NC}" >&2
        echo "$creds" >&2
        return 1
    fi
    
    # Export credentials
    export AWS_ACCESS_KEY_ID=$(echo "$creds" | jq -r .Credentials.AccessKeyId)
    export AWS_SECRET_ACCESS_KEY=$(echo "$creds" | jq -r .Credentials.SecretAccessKey)
    export AWS_SESSION_TOKEN=$(echo "$creds" | jq -r .Credentials.SessionToken)
    
    # Store expiration for auto-refresh
    export SUNKWORKS_SESSION_EXPIRES=$(echo "$creds" | jq -r .Credentials.Expiration)
    export SUNKWORKS_SESSION_ENV="$env"
    export SUNKWORKS_MFA_METHOD="$method"
    
    local last3="${ACCOUNT_ID: -3}"
    local expires_human=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$SUNKWORKS_SESSION_EXPIRES" "+%H:%M:%S" 2>/dev/null || echo "$SUNKWORKS_SESSION_EXPIRES")
    
    echo -e "${GREEN}✓ Sunkworks MFA session active for ${env} (account ...${last3})${NC}"
    echo -e "${BLUE}  Method: ${method}${NC}"
    echo -e "${BLUE}  Expires: ${expires_human}${NC}"
    echo -e "${BLUE}  Duration: $((SESSION_DURATION / 60)) minutes${NC}"
    
    return 0
}

# -----------------------------------------------------------------------------
# Session Refresh (for long streams)
# -----------------------------------------------------------------------------

sunkworks_session_check() {
    if [ -z "${SUNKWORKS_SESSION_EXPIRES:-}" ]; then
        echo -e "${YELLOW}No active Sunkworks session${NC}"
        return 1
    fi
    
    local expires_epoch
    local now_epoch
    
    # Try to parse expiration
    expires_epoch=$(date -j -f "%Y-%m-%dT%H:%M:%SZ" "$SUNKWORKS_SESSION_EXPIRES" "+%s" 2>/dev/null) || {
        echo -e "${RED}Cannot parse session expiration${NC}"
        return 1
    }
    
    now_epoch=$(date "+%s")
    local remaining=$((expires_epoch - now_epoch))
    
    if [ $remaining -le 0 ]; then
        echo -e "${RED}Session expired!${NC}"
        return 1
    elif [ $remaining -le $REFRESH_THRESHOLD ]; then
        echo -e "${YELLOW}⚠️  Session expires in ${remaining}s - consider refreshing${NC}"
        return 2
    else
        echo -e "${GREEN}✓ Session valid for $((remaining / 60))m $((remaining % 60))s${NC}"
        return 0
    fi
}

sunkworks_session_refresh() {
    if [ -z "${SUNKWORKS_SESSION_ENV:-}" ]; then
        echo -e "${RED}Error: No previous session to refresh${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}🔄 Refreshing session for ${SUNKWORKS_SESSION_ENV}...${NC}"
    
    # Use stored method preference
    export MFA_METHOD="${SUNKWORKS_MFA_METHOD:-auto}"
    
    sunkworks_mfa "$SUNKWORKS_SESSION_ENV"
}

# -----------------------------------------------------------------------------
# Background Session Monitor (for streams)
# -----------------------------------------------------------------------------

sunkworks_session_monitor() {
    local check_interval="${1:-60}"  # Check every 60 seconds by default
    
    echo -e "${BLUE}🔍 Starting session monitor (check every ${check_interval}s)${NC}"
    echo -e "${YELLOW}Press Ctrl+C to stop${NC}"
    
    while true; do
        local status
        sunkworks_session_check
        status=$?
        
        if [ $status -eq 1 ]; then
            # Session expired
            echo -e "${YELLOW}Session expired, attempting refresh...${NC}"
            sunkworks_session_refresh || {
                echo -e "${RED}Auto-refresh failed! Manual intervention needed.${NC}"
                # Could send notification here
            }
        elif [ $status -eq 2 ]; then
            # Near expiration
            echo -e "${YELLOW}Session nearing expiration, auto-refreshing...${NC}"
            sunkworks_session_refresh
        fi
        
        sleep "$check_interval"
    done
}

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------

sunkworks_mfa_help() {
    echo -e "${BLUE}Sunkworks Enhanced MFA${NC}"
    echo ""
    echo "Commands:"
    echo "  sunkworks_mfa [env]        - Get MFA session (auto-detect method)"
    echo "  sunkworks_session_check    - Check session expiration"
    echo "  sunkworks_session_refresh  - Refresh current session"
    echo "  sunkworks_session_monitor  - Background session monitor"
    echo ""
    echo "Environment Variables:"
    echo "  MFA_METHOD         - Force method: auto, yubikey, 1password, manual"
    echo "  SESSION_DURATION   - Session length in seconds (default: 3600)"
    echo "  REFRESH_THRESHOLD  - Refresh when seconds remaining (default: 300)"
    echo "  YUBIKEY_CREDENTIAL - YubiKey OATH credential name (default: aws-{env})"
    echo ""
    echo "YubiKey Setup:"
    echo "  1. Install ykman: brew install ykman"
    echo "  2. Add OATH credential: ykman oath accounts add aws-sb <secret>"
    echo "  3. Or use YubiKey Authenticator GUI"
    echo ""
    echo "Example .env.sb:"
    echo "  ACCOUNT_ID=123456789012"
    echo "  MFA_DEVICE_NAME=my-yubikey"
    echo "  OP_VAULT_ITEM=op://Vault/AWS-SB/one-time password?attribute=otp"
}

# Export functions
export -f sunkworks_detect_yubikey
export -f sunkworks_get_yubikey_totp
export -f sunkworks_get_1password_totp
export -f sunkworks_detect_mfa_method
export -f sunkworks_get_mfa_code
export -f sunkworks_mfa
export -f sunkworks_session_check
export -f sunkworks_session_refresh
export -f sunkworks_session_monitor
export -f sunkworks_mfa_help
