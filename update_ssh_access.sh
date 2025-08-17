#!/bin/bash

# SSH Access Updater Script
# Updates EC2 security group to allow SSH access from current public IP only

set -e

# Configuration
REGION="eu-west-1"
SECURITY_GROUP_ID="sg-0d819a7d8bef10a60"
ENV_FILE=".env"

# Colors for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔒 SSH Access Updater${NC}"
echo "=================================="

# Get current public IP
echo -n "Getting current public IP... "
CURRENT_IP=$(curl -s https://ipinfo.io/ip)
if [ -z "$CURRENT_IP" ]; then
    echo -e "${RED}✗ Failed to get public IP${NC}"
    exit 1
fi
echo -e "${GREEN}✓ $CURRENT_IP${NC}"

# Store IP in .env file
echo -n "Updating .env file... "
if [ -f "$ENV_FILE" ]; then
    # Remove existing MY_PUBLIC_IP line if it exists
    grep -v "^MY_PUBLIC_IP=" "$ENV_FILE" > "${ENV_FILE}.tmp" 2>/dev/null || touch "${ENV_FILE}.tmp"
    mv "${ENV_FILE}.tmp" "$ENV_FILE"
fi
echo "MY_PUBLIC_IP=$CURRENT_IP" >> "$ENV_FILE"
echo -e "${GREEN}✓ Stored in $ENV_FILE${NC}"

# Get current security group rules
echo -n "Checking current SSH rules... "
CURRENT_RULES=$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --group-ids "$SECURITY_GROUP_ID" \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`].IpRanges[].CidrIp' \
    --output text 2>/dev/null || echo "")

if [ -n "$CURRENT_RULES" ]; then
    echo -e "${YELLOW}Found existing SSH rules: $CURRENT_RULES${NC}"
    
    # Remove existing SSH rules
    echo -n "Removing old SSH rules... "
    for cidr in $CURRENT_RULES; do
        aws ec2 revoke-security-group-ingress \
            --region "$REGION" \
            --group-id "$SECURITY_GROUP_ID" \
            --protocol tcp \
            --port 22 \
            --cidr "$cidr" >/dev/null 2>&1 || true
    done
    echo -e "${GREEN}✓ Cleaned up${NC}"
else
    echo -e "${GREEN}✓ No existing SSH rules${NC}"
fi

# Add new SSH rule for current IP
echo -n "Adding SSH access for $CURRENT_IP... "
aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol tcp \
    --port 22 \
    --cidr "${CURRENT_IP}/32" >/dev/null

echo -e "${GREEN}✓ SSH access granted${NC}"

# Verify the change
echo -n "Verifying new rules... "
NEW_RULES=$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --group-ids "$SECURITY_GROUP_ID" \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`].IpRanges[].CidrIp' \
    --output text)

if [[ "$NEW_RULES" == "${CURRENT_IP}/32" ]]; then
    echo -e "${GREEN}✓ Verified${NC}"
else
    echo -e "${RED}✗ Verification failed${NC}"
    exit 1
fi

echo ""
echo -e "${GREEN}🎉 SSH access updated successfully!${NC}"
echo "Your IP: $CURRENT_IP"
echo "Security Group: $SECURITY_GROUP_ID"
echo "Instance: 3.254.57.73 (tf-bastion)"
echo ""
echo "You can now SSH to your instance:"
echo -e "${YELLOW}ssh ec2-user@3.254.57.73${NC}"
echo ""
echo "💡 Run this script again if your IP changes"