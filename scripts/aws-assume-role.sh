#!/bin/bash
# File: scripts/aws-assume-role.sh
# Convenience wrapper for assuming AWS roles via GitHub OIDC

set -euo pipefail

ROLE_NAME="${1:-}"
ENVIRONMENT="${2:-sb}"
DURATION="${3:-3600}"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Help text
if [ -z "${ROLE_NAME}" ] || [ "${ROLE_NAME}" = "-h" ] || [ "${ROLE_NAME}" = "--help" ]; then
    echo -e "${BLUE}🔑 AWS Role Assumption Helper${NC}"
    echo ""
    echo "Usage: $0 <role-name> [environment] [duration]"
    echo ""
    echo "Available roles:"
    echo "  ReadOnly   - Read-only access for investigation (4h default)"
    echo "  Billing    - Billing and cost management (2h default)" 
    echo "  Security   - Security and IAM administration (1h default)"
    echo "  Developer  - Application development (8h default)"
    echo "  Admin      - Full administrative access (1h default)"
    echo "  CI         - Infrastructure as code (12h default)"
    echo ""
    echo "Examples:"
    echo "  $0 ReadOnly sb"
    echo "  $0 Billing prod 7200"
    echo "  $0 Developer sb"
    echo "  $0 Admin prod"
    echo ""
    echo "Environment files needed:"
    echo "  .env.sb with ACCOUNT_ID"
    echo "  .env.prod with ACCOUNT_ID"
    exit 0
fi

# Load environment configuration
ENV_FILE=".env.${ENVIRONMENT}"
if [ ! -f "${ENV_FILE}" ]; then
    echo -e "${RED}❌ Environment file not found: ${ENV_FILE}${NC}"
    echo ""
    echo "Create ${ENV_FILE} with:"
    echo "  ACCOUNT_ID=123456789012"
    exit 1
fi

# Source environment file
set -a
source "${ENV_FILE}"
set +a

if [ -z "${ACCOUNT_ID:-}" ]; then
    echo -e "${RED}❌ ACCOUNT_ID not set in ${ENV_FILE}${NC}"
    exit 1
fi

# Role-specific default durations
case "${ROLE_NAME}" in
    "ReadOnly")
        DEFAULT_DURATION=14400  # 4 hours
        ;;
    "Billing")
        DEFAULT_DURATION=7200   # 2 hours
        ;;
    "Security"|"Admin")
        DEFAULT_DURATION=3600   # 1 hour
        ;;
    "Developer")
        DEFAULT_DURATION=28800  # 8 hours
        ;;
    "CI")
        DEFAULT_DURATION=43200  # 12 hours
        ;;
    *)
        echo -e "${RED}❌ Unknown role: ${ROLE_NAME}${NC}"
        echo "Available roles: ReadOnly, Billing, Security, Developer, Admin, CI"
        exit 1
        ;;
esac

# Use provided duration or role default
FINAL_DURATION="${DURATION}"
if [ "${DURATION}" = "3600" ]; then  # Default from parameter
    FINAL_DURATION="${DEFAULT_DURATION}"
fi

ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ENVIRONMENT}-${ROLE_NAME}"
SESSION_NAME="local-${ROLE_NAME}-$(date +%s)"

echo -e "${BLUE}🚀 Assuming AWS Role${NC}"
echo "Environment: ${ENVIRONMENT}"
echo "Role: ${ROLE_NAME}"
echo "ARN: ${ROLE_ARN}"
echo "Duration: ${FINAL_DURATION}s ($(( FINAL_DURATION / 3600 ))h $(( (FINAL_DURATION % 3600) / 60 ))m)"
echo ""

# Call the OIDC authentication script
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
"${SCRIPT_DIR}/gh-aws-auth.sh" "${ROLE_ARN}" "${SESSION_NAME}" "${FINAL_DURATION}"