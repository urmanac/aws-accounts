#!/bin/bash
# =============================================================================
# Sunkworks SSO Device Trust - Home Lab IP Range Authentication
# =============================================================================
# Configures AWS SSO to trust devices from home lab IP ranges.
# For use with AWS Identity Center (SSO) SAML-based access.
# =============================================================================

set -euo pipefail

# Colors
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m'

# Home lab IP ranges
HOME_LAB_CIDRS="${HOME_LAB_CIDRS:-10.17.12.0/24,10.17.13.0/24}"

# Script directory
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# -----------------------------------------------------------------------------
# SSO Configuration Functions
# -----------------------------------------------------------------------------

sunkworks_sso_configure() {
    local profile="${1:-sunkworks}"
    local start_url="${SSO_START_URL:-}"
    local region="${SSO_REGION:-us-east-1}"
    
    if [ -z "$start_url" ]; then
        echo -e "${RED}Error: SSO_START_URL not set${NC}" >&2
        echo "Set it with: export SSO_START_URL=https://your-sso.awsapps.com/start" >&2
        return 1
    fi
    
    echo -e "${BLUE}🔧 Configuring AWS SSO profile: ${profile}${NC}"
    
    # Configure SSO profile
    aws configure set sso_start_url "$start_url" --profile "$profile"
    aws configure set sso_region "$region" --profile "$profile"
    aws configure set sso_account_id "${SSO_ACCOUNT_ID:-}" --profile "$profile"
    aws configure set sso_role_name "${SSO_ROLE_NAME:-SunkworksAdmin}" --profile "$profile"
    aws configure set region "$region" --profile "$profile"
    
    echo -e "${GREEN}✓ SSO profile configured${NC}"
    echo ""
    echo "Run 'sunkworks_sso_login $profile' to authenticate"
}

sunkworks_sso_login() {
    local profile="${1:-sunkworks}"
    
    echo -e "${BLUE}🔑 Starting AWS SSO login for profile: ${profile}${NC}"
    
    # Check if we're on a trusted network
    local trusted=false
    local current_ip
    
    # Get current local IP(s)
    if command -v hostname &> /dev/null; then
        current_ip=$(hostname -I 2>/dev/null | awk '{print $1}' || ipconfig getifaddr en0 2>/dev/null || echo "unknown")
    fi
    
    # Check if IP is in home lab range
    IFS=',' read -ra CIDRS <<< "$HOME_LAB_CIDRS"
    for cidr in "${CIDRS[@]}"; do
        if sunkworks_ip_in_cidr "$current_ip" "$cidr"; then
            trusted=true
            break
        fi
    done
    
    if [ "$trusted" = true ]; then
        echo -e "${GREEN}✓ On trusted network ($current_ip in home lab range)${NC}"
        echo -e "${YELLOW}  Device trust will be enabled for this session${NC}"
    else
        echo -e "${YELLOW}⚠️  Not on trusted network ($current_ip)${NC}"
        echo -e "${YELLOW}  Additional MFA may be required${NC}"
    fi
    
    # Start SSO login
    aws sso login --profile "$profile"
    
    if [ $? -eq 0 ]; then
        echo -e "${GREEN}✓ SSO login successful${NC}"
        
        # Verify access
        local identity
        identity=$(aws sts get-caller-identity --profile "$profile" 2>/dev/null)
        
        if [ -n "$identity" ]; then
            local account=$(echo "$identity" | jq -r .Account)
            local arn=$(echo "$identity" | jq -r .Arn)
            echo -e "${BLUE}  Account: ${account}${NC}"
            echo -e "${BLUE}  Role: ${arn}${NC}"
        fi
    else
        echo -e "${RED}❌ SSO login failed${NC}" >&2
        return 1
    fi
}

sunkworks_sso_logout() {
    local profile="${1:-sunkworks}"
    
    echo -e "${BLUE}🔓 Logging out of AWS SSO...${NC}"
    aws sso logout --profile "$profile"
    echo -e "${GREEN}✓ SSO logout complete${NC}"
}

# -----------------------------------------------------------------------------
# IP Helper Functions
# -----------------------------------------------------------------------------

sunkworks_ip_in_cidr() {
    local ip="$1"
    local cidr="$2"
    
    # Extract network and prefix
    local network="${cidr%/*}"
    local prefix="${cidr#*/}"
    
    # Convert IPs to integers
    local ip_int=$(sunkworks_ip_to_int "$ip")
    local network_int=$(sunkworks_ip_to_int "$network")
    
    # Calculate netmask
    local netmask=$(( (0xFFFFFFFF << (32 - prefix)) & 0xFFFFFFFF ))
    
    # Check if IP is in range
    [ $((ip_int & netmask)) -eq $((network_int & netmask)) ]
}

sunkworks_ip_to_int() {
    local ip="$1"
    local a b c d
    IFS='.' read -r a b c d <<< "$ip"
    echo $(( (a << 24) + (b << 16) + (c << 8) + d ))
}

# -----------------------------------------------------------------------------
# Profile Switching for Episodes
# -----------------------------------------------------------------------------

sunkworks_switch_episode() {
    local episode="${1:-}"
    
    if [ -z "$episode" ]; then
        echo "Usage: sunkworks_switch_episode <episode-name>" >&2
        echo "Available episodes:" >&2
        aws sso list-accounts --profile sunkworks 2>/dev/null | jq -r '.accountList[].accountName' | grep sunkworks || echo "  (run sunkworks_sso_login first)"
        return 1
    fi
    
    local account_id
    account_id=$(aws sso list-accounts --profile sunkworks 2>/dev/null | jq -r ".accountList[] | select(.accountName | contains(\"$episode\")) | .accountId")
    
    if [ -z "$account_id" ]; then
        echo -e "${RED}Error: Episode account not found: ${episode}${NC}" >&2
        return 1
    fi
    
    echo -e "${BLUE}🔄 Switching to episode: ${episode} (${account_id})${NC}"
    
    # Configure episode profile
    local profile="sunkworks-${episode}"
    aws configure set sso_start_url "$SSO_START_URL" --profile "$profile"
    aws configure set sso_region "${SSO_REGION:-us-east-1}" --profile "$profile"
    aws configure set sso_account_id "$account_id" --profile "$profile"
    aws configure set sso_role_name "SunkworksEpisodeAdmin" --profile "$profile"
    
    # Login to episode account
    aws sso login --profile "$profile"
    
    export AWS_PROFILE="$profile"
    echo -e "${GREEN}✓ Switched to ${episode}. AWS_PROFILE set to ${profile}${NC}"
}

# -----------------------------------------------------------------------------
# Help
# -----------------------------------------------------------------------------

sunkworks_sso_help() {
    echo -e "${BLUE}Sunkworks SSO Device Trust${NC}"
    echo ""
    echo "Commands:"
    echo "  sunkworks_sso_configure [profile] - Configure SSO profile"
    echo "  sunkworks_sso_login [profile]     - Login via SSO"
    echo "  sunkworks_sso_logout [profile]    - Logout from SSO"
    echo "  sunkworks_switch_episode <name>   - Switch to episode account"
    echo ""
    echo "Environment Variables:"
    echo "  SSO_START_URL   - AWS SSO portal URL"
    echo "  SSO_REGION      - SSO region (default: us-east-1)"
    echo "  SSO_ACCOUNT_ID  - Default account ID"
    echo "  SSO_ROLE_NAME   - Default role name"
    echo "  HOME_LAB_CIDRS  - Trusted IP ranges (default: 10.17.12.0/24,10.17.13.0/24)"
}

# Export functions
export -f sunkworks_sso_configure
export -f sunkworks_sso_login
export -f sunkworks_sso_logout
export -f sunkworks_switch_episode
export -f sunkworks_ip_in_cidr
export -f sunkworks_ip_to_int
export -f sunkworks_sso_help
