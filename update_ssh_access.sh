#!/bin/bash
# SSH Access Updater Script
# Updates EC2 security group to allow SSH access from current public IP only,
# and prints out the current bastion instance IP + SSH command.

set -euo pipefail

# --- Configuration ---
REGION="eu-west-1"
ASG_NAME="bastion-asg"
SECURITY_GROUP_NAME="sandbox-eu-bastion-sg"
ENV_FILE=".env"

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔒 SSH Access Updater${NC}"
echo "=================================="

# --- Get current public IP ---
echo -n "Getting current public IP... "
CURRENT_IP="$(curl -s https://ipinfo.io/ip || true)"
if [ -z "$CURRENT_IP" ]; then
    echo -e "${RED}✗ Failed to get public IP${NC}"
    exit 1
fi
echo -e "${GREEN}✓ $CURRENT_IP${NC}"

# --- Store IP in .env file ---
echo -n "Updating $ENV_FILE... "
if [ -f "$ENV_FILE" ]; then
    grep -v "^MY_PUBLIC_IP=" "$ENV_FILE" > "${ENV_FILE}.tmp" || true
    mv "${ENV_FILE}.tmp" "$ENV_FILE"
fi
echo "MY_PUBLIC_IP=$CURRENT_IP" >> "$ENV_FILE"
echo -e "${GREEN}✓ Stored in $ENV_FILE${NC}"

# --- Look up Security Group ID by name ---
echo -n "Looking up Security Group '$SECURITY_GROUP_NAME'... "
SECURITY_GROUP_ID="$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --filters "Name=group-name,Values=$SECURITY_GROUP_NAME" \
    --query 'SecurityGroups[0].GroupId' \
    --output text 2>/dev/null || true)"
if [ -z "$SECURITY_GROUP_ID" ] || [ "$SECURITY_GROUP_ID" = "None" ]; then
    echo -e "${RED}✗ Failed to find Security Group${NC}"
    exit 1
fi
echo -e "${GREEN}✓ $SECURITY_GROUP_ID${NC}"

# --- Get current SSH rules ---
echo -n "Checking current SSH rules... "
CURRENT_RULES="$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --group-ids "$SECURITY_GROUP_ID" \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`].IpRanges[].CidrIp' \
    --output text 2>/dev/null || true)"

if [ -n "$CURRENT_RULES" ]; then
    echo -e "${YELLOW}Found existing SSH rules: $CURRENT_RULES${NC}"
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

# --- Add new SSH rule for current IP ---
echo -n "Adding SSH access for $CURRENT_IP... "
aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol tcp \
    --port 22 \
    --cidr "${CURRENT_IP}/32" >/dev/null
echo -e "${GREEN}✓ SSH access granted${NC}"

# --- Verify the change ---
echo -n "Verifying new rules... "
NEW_RULES="$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --group-ids "$SECURITY_GROUP_ID" \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`].IpRanges[].CidrIp' \
    --output text)"
if [[ "$NEW_RULES" == "${CURRENT_IP}/32" ]]; then
    echo -e "${GREEN}✓ Verified${NC}"
else
    echo -e "${RED}✗ Verification failed${NC}"
    exit 1
fi

# --- Find bastion instance from ASG ---
echo -n "Looking up bastion instance from ASG '$ASG_NAME'... "
INSTANCE_ID="$(aws autoscaling describe-auto-scaling-groups \
    --region "$REGION" \
    --auto-scaling-group-names "$ASG_NAME" \
    --query 'AutoScalingGroups[0].Instances[0].InstanceId' \
    --output text 2>/dev/null || true)"
if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
    echo -e "${RED}✗ Failed to find instance in ASG${NC}"
    exit 1
fi
echo -e "${GREEN}✓ $INSTANCE_ID${NC}"

echo -n "Looking up public IP of $INSTANCE_ID... "
INSTANCE_IP="$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text 2>/dev/null || true)"
if [ -z "$INSTANCE_IP" ] || [ "$INSTANCE_IP" = "None" ]; then
    echo -e "${RED}✗ Instance has no public IP${NC}"
    exit 1
fi
echo -e "${GREEN}✓ $INSTANCE_IP${NC}"

echo ""
echo -e "${GREEN}🎉 SSH access updated successfully!${NC}"
echo "Your IP: $CURRENT_IP"
echo "Security Group: $SECURITY_GROUP_NAME ($SECURITY_GROUP_ID)"
echo "Bastion Instance: $INSTANCE_ID"
echo "Public IP: $INSTANCE_IP"
echo ""
echo "You can now SSH to your instance:"
echo -e "${YELLOW}ssh ec2-user@${INSTANCE_IP}${NC}"
echo ""
echo "💡 Run this script again if your IP changes"
