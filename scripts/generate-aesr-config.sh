#!/bin/bash
# File: scripts/generate-aesr-config.sh
# Generates AWS Extend Switch Roles configuration for OIDC-enabled roles

set -euo pipefail

ENVIRONMENT="${1:-sb}"
ACCOUNT_ID="${2:-$(aws sts get-caller-identity --query Account --output text 2>/dev/null || echo 'ACCOUNT_ID')}"
OUTPUT_FILE="${3:-aesr-config-${ENVIRONMENT}.json}"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔧 Generating AESR Configuration${NC}"
echo "Environment: ${ENVIRONMENT}"
echo "Account ID: ${ACCOUNT_ID}"
echo "Output: ${OUTPUT_FILE}"
echo ""

# Generate AESR configuration
cat > "${OUTPUT_FILE}" << EOF
{
  "profiles": [
    {
      "profile": "${ENVIRONMENT}-ReadOnly",
      "role_arn": "arn:aws:iam::${ACCOUNT_ID}:role/${ENVIRONMENT}-ReadOnly",
      "color": "4CAF50",
      "image": "🔍",
      "region": "us-east-1"
    },
    {
      "profile": "${ENVIRONMENT}-Billing", 
      "role_arn": "arn:aws:iam::${ACCOUNT_ID}:role/${ENVIRONMENT}-Billing",
      "color": "FF9800",
      "image": "💰",
      "region": "us-east-1"
    },
    {
      "profile": "${ENVIRONMENT}-Security",
      "role_arn": "arn:aws:iam::${ACCOUNT_ID}:role/${ENVIRONMENT}-Security", 
      "color": "9C27B0",
      "image": "🔒",
      "region": "us-east-1"
    },
    {
      "profile": "${ENVIRONMENT}-Developer",
      "role_arn": "arn:aws:iam::${ACCOUNT_ID}:role/${ENVIRONMENT}-Developer",
      "color": "2196F3", 
      "image": "🛠️",
      "region": "us-east-1"
    },
    {
      "profile": "${ENVIRONMENT}-Admin",
      "role_arn": "arn:aws:iam::${ACCOUNT_ID}:role/${ENVIRONMENT}-Admin",
      "color": "F44336",
      "image": "⚠️",
      "region": "us-east-1"
    },
    {
      "profile": "${ENVIRONMENT}-CI",
      "role_arn": "arn:aws:iam::${ACCOUNT_ID}:role/${ENVIRONMENT}-CI",
      "color": "607D8B",
      "image": "🤖",
      "region": "us-east-1"
    }
  ]
}
EOF

echo -e "${GREEN}✓ AESR configuration generated: ${OUTPUT_FILE}${NC}"
echo ""
echo -e "${YELLOW}📋 Installation Instructions:${NC}"
echo "1. Install AWS Extend Switch Roles browser extension"
echo "2. Open extension options"
echo "3. Import the generated configuration file"
echo "4. Configure your authentication method (GitHub OIDC)"
echo ""
echo -e "${YELLOW}🔗 Browser Extension URLs:${NC}"
echo "Chrome: https://chrome.google.com/webstore/detail/aws-extend-switch-roles/jpmkfafbacpgapdghgdpembnojdlgkdl"
echo "Firefox: https://addons.mozilla.org/en-US/firefox/addon/aws-extend-switch-roles/"
echo ""
echo -e "${YELLOW}💡 Note:${NC} You'll need to configure OIDC authentication separately"
echo "See docs/github-oidc-integration.md for setup instructions"