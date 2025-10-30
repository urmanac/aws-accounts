#!/bin/bash
# File: scripts/gh-aws-auth.sh
# Exchanges GitHub token for AWS credentials via OIDC role assumption

set -euo pipefail

ROLE_ARN="${1}"
SESSION_NAME="${2:-github-cli-session}"
DURATION="${3:-3600}"

# Colors for output
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${BLUE}🔑 GitHub OIDC → AWS Role Assumption${NC}"
echo "Role: ${ROLE_ARN}"
echo "Session: ${SESSION_NAME}"
echo "Duration: ${DURATION}s"
echo ""

# Check prerequisites
if ! command -v gh &> /dev/null; then
    echo -e "${RED}❌ GitHub CLI (gh) not found${NC}"
    echo "Install: brew install gh"
    exit 1
fi

if ! command -v jq &> /dev/null; then
    echo -e "${RED}❌ jq not found${NC}"
    echo "Install: brew install jq"
    exit 1
fi

# Check GitHub authentication
if ! gh auth status &> /dev/null; then
    echo -e "${RED}❌ Not authenticated with GitHub${NC}"
    echo "Run: gh auth login"
    exit 1
fi

echo -e "${YELLOW}📝 Getting GitHub token...${NC}"
GH_TOKEN=$(gh auth token)

if [ -z "${GH_TOKEN}" ]; then
    echo -e "${RED}❌ Failed to get GitHub token${NC}"
    exit 1
fi

echo -e "${YELLOW}🔄 Exchanging token for AWS credentials...${NC}"

# Exchange for AWS credentials
if CREDENTIALS=$(aws sts assume-role-with-web-identity \
  --role-arn "${ROLE_ARN}" \
  --role-session-name "${SESSION_NAME}" \
  --web-identity-token "${GH_TOKEN}" \
  --duration-seconds "${DURATION}" 2>/dev/null); then
  
  # Export credentials
  export AWS_ACCESS_KEY_ID=$(echo $CREDENTIALS | jq -r .Credentials.AccessKeyId)
  export AWS_SECRET_ACCESS_KEY=$(echo $CREDENTIALS | jq -r .Credentials.SecretAccessKey) 
  export AWS_SESSION_TOKEN=$(echo $CREDENTIALS | jq -r .Credentials.SessionToken)
  
  # Verify credentials work
  if AWS_IDENTITY=$(aws sts get-caller-identity 2>/dev/null); then
    ASSUMED_ROLE_ARN=$(echo $AWS_IDENTITY | jq -r .Arn)
    ACCOUNT_ID=$(echo $AWS_IDENTITY | jq -r .Account)
    
    echo -e "${GREEN}✓ AWS credentials configured successfully${NC}"
    echo "Account: ${ACCOUNT_ID}"
    echo "Role: ${ASSUMED_ROLE_ARN}"
    echo "Expires: $(date -d "+${DURATION} seconds" '+%Y-%m-%d %H:%M:%S')"
    echo ""
    echo -e "${YELLOW}💡 Credentials are now available in environment variables:${NC}"
    echo "  AWS_ACCESS_KEY_ID"
    echo "  AWS_SECRET_ACCESS_KEY" 
    echo "  AWS_SESSION_TOKEN"
    echo ""
    echo -e "${YELLOW}🔧 To use in current shell:${NC}"
    echo "  source <(${0} ${ROLE_ARN} ${SESSION_NAME} ${DURATION})"
  else
    echo -e "${RED}❌ Failed to verify AWS credentials${NC}"
    exit 1
  fi
  
else
  echo -e "${RED}❌ Failed to assume role${NC}"
  echo "Possible issues:"
  echo "  - Role trust policy doesn't allow your GitHub repository"
  echo "  - Role doesn't exist or is misconfigured"
  echo "  - GitHub token doesn't have required claims"
  echo "  - Network connectivity issues"
  exit 1
fi