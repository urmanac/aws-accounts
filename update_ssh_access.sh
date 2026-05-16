#!/bin/bash
# SSH Access Updater Script
# Updates EC2 security group to allow SSH access from current public IP only,
# and prints out the current bastion instance IP + SSH command.

set -euo pipefail

# --- Configuration ---
REGION="eu-west-1"
SECURITY_GROUP_NAME="sandbox-eu-bastion-sg"
ENV_FILE=".env"
INSTANCE_TAG_NAME="tf-bastion"  # Tag name to find the bastion instance

# --- Colors ---
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

echo -e "${YELLOW}🔒 SSH Access Updater${NC}"
echo "=================================="

# --- Get current public IP (IPv4) ---
echo -n "Getting current public IPv4... "
CURRENT_IP="$(curl -s https://ipinfo.io/ip || true)"
if [ -z "$CURRENT_IP" ]; then
    echo -e "${RED}✗ Failed to get IPv4 address${NC}"
    exit 1
fi
echo -e "${GREEN}✓ IPv4 $CURRENT_IP${NC}"

# --- Get current public IP (IPv6) ---
echo -n "Getting current public IPv6... "
CURRENT_IPV6="$(curl -s -6 https://api64.ipify.org || true)"
if [ -z "$CURRENT_IPV6" ]; then
    echo -e "${YELLOW}⚠ No IPv6 address detected${NC}"
else
    echo -e "${GREEN}✓ IPv6 $CURRENT_IPV6${NC}"
fi

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

# --- Get current SSH rules (IPv4) ---
echo -n "Checking current IPv4 SSH rules... "
CURRENT_RULES_IPV4="$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --group-ids "$SECURITY_GROUP_ID" \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`].IpRanges[].CidrIp' \
    --output text 2>/dev/null || true)"

if [ -n "$CURRENT_RULES_IPV4" ]; then
    echo -e "${YELLOW}Found existing IPv4 SSH rules: $CURRENT_RULES_IPV4${NC}"
    echo -n "Removing old IPv4 SSH rules... "
    for cidr in $CURRENT_RULES_IPV4; do
        aws ec2 revoke-security-group-ingress \
            --region "$REGION" \
            --group-id "$SECURITY_GROUP_ID" \
            --protocol tcp \
            --port 22 \
            --cidr "$cidr" >/dev/null 2>&1 || true
    done
    echo -e "${GREEN}✓ IPv4 rules cleaned${NC}"
else
    echo -e "${GREEN}✓ No existing IPv4 SSH rules${NC}"
fi

# --- Get current SSH rules (IPv6) ---
echo -n "Checking current IPv6 SSH rules... "
CURRENT_RULES_IPV6="$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --group-ids "$SECURITY_GROUP_ID" \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`].Ipv6Ranges[].CidrIpv6' \
    --output text 2>/dev/null || true)"

if [ -n "$CURRENT_RULES_IPV6" ]; then
    echo -e "${YELLOW}Found existing IPv6 SSH rules: $CURRENT_RULES_IPV6${NC}"
    echo -n "Removing old IPv6 SSH rules... "
    for cidr in $CURRENT_RULES_IPV6; do
        aws ec2 revoke-security-group-ingress \
            --region "$REGION" \
            --group-id "$SECURITY_GROUP_ID" \
            --ip-permissions 'IpProtocol=tcp,FromPort=22,ToPort=22,Ipv6Ranges=[{CidrIpv6='"$cidr"'}]' >/dev/null 2>&1 || true
    done
    echo -e "${GREEN}✓ IPv6 rules cleaned${NC}"
else
    echo -e "${GREEN}✓ No existing IPv6 SSH rules${NC}"
fi

# --- Add new SSH rule for current IPv4 IP ---
echo -n "Adding IPv4 SSH access for $CURRENT_IP... "
aws ec2 authorize-security-group-ingress \
    --region "$REGION" \
    --group-id "$SECURITY_GROUP_ID" \
    --protocol tcp \
    --port 22 \
    --cidr "${CURRENT_IP}/32" >/dev/null
echo -e "${GREEN}✓ IPv4 SSH access granted${NC}"

# --- Add new SSH rule for current IPv6 IP ---
if [ -n "$CURRENT_IPV6" ]; then
    echo -n "Adding IPv6 SSH access for $CURRENT_IPV6... "
    aws ec2 authorize-security-group-ingress \
        --region "$REGION" \
        --group-id "$SECURITY_GROUP_ID" \
        --ip-permissions 'IpProtocol=tcp,FromPort=22,ToPort=22,Ipv6Ranges=[{CidrIpv6='"${CURRENT_IPV6}/128"'}]' >/dev/null
    echo -e "${GREEN}✓ IPv6 SSH access granted${NC}"
fi
# --- Verify IPv4 rule ---
echo -n "Verifying new IPv4 rule... "
NEW_RULES_IPV4="$(aws ec2 describe-security-groups \
    --region "$REGION" \
    --group-ids "$SECURITY_GROUP_ID" \
    --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`].IpRanges[].CidrIp' \
    --output text)"
if [[ "$NEW_RULES_IPV4" == "${CURRENT_IP}/32" ]]; then
    echo -e "${GREEN}✓ IPv4 verified${NC}"
else
    echo -e "${RED}✗ IPv4 verification failed${NC}"
    exit 1
fi

# --- Verify IPv6 rule ---
if [ -n "$CURRENT_IPV6" ]; then
    echo -n "Verifying new IPv6 rule... "
    NEW_RULES_IPV6="$(aws ec2 describe-security-groups \
        --region "$REGION" \
        --group-ids "$SECURITY_GROUP_ID" \
        --query 'SecurityGroups[0].IpPermissions[?FromPort==`22`].Ipv6Ranges[].CidrIpv6' \
        --output text)"
    if [[ "$NEW_RULES_IPV6" == "${CURRENT_IPV6}/128" ]]; then
        echo -e "${GREEN}✓ IPv6 verified${NC}"
    else
        echo -e "${RED}✗ IPv6 verification failed${NC}"
        exit 1
    fi
fi

# --- Find bastion instance by tag ---
echo -n "Looking up bastion instance with tag '$INSTANCE_TAG_NAME'... "
INSTANCE_ID="$(aws ec2 describe-instances \
    --region "$REGION" \
    --filters "Name=tag:Name,Values=$INSTANCE_TAG_NAME" "Name=instance-state-name,Values=running" \
    --query 'Reservations[0].Instances[0].InstanceId' \
    --output text 2>/dev/null || true)"
if [ -z "$INSTANCE_ID" ] || [ "$INSTANCE_ID" = "None" ]; then
    echo -e "${RED}✗ Failed to find running instance with tag '$INSTANCE_TAG_NAME'${NC}"
    exit 1
fi
echo -e "${GREEN}✓ $INSTANCE_ID${NC}"

echo -n "Looking up instance network details... "

# Get private IP (always available)
INSTANCE_PRIVATE_IP="$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PrivateIpAddress' \
    --output text 2>/dev/null || true)"

# Check for public IPv4 (may not exist in IPv6-only setup)
INSTANCE_IPv4="$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text 2>/dev/null || true)"

# Check for IPv6 addresses
INSTANCE_IPv6="$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].NetworkInterfaces[0].Ipv6Addresses[0].Ipv6Address' \
    --output text 2>/dev/null || true)"

# Validate that we have at least private IP
if [ -z "$INSTANCE_PRIVATE_IP" ] || [ "$INSTANCE_PRIVATE_IP" = "None" ]; then
    echo -e "${RED}✗ Instance has no private IP${NC}"
    exit 1
fi

echo -e "${GREEN}✓ Private IP: $INSTANCE_PRIVATE_IP${NC}"

# Check public connectivity
HAS_PUBLIC_ACCESS=false
if [ -n "$INSTANCE_IPv4" ] && [ "$INSTANCE_IPv4" != "None" ]; then
    echo -e "${GREEN}✓ IPv4: $INSTANCE_IPv4${NC}"
    HAS_PUBLIC_ACCESS=true
fi

if [ -n "$INSTANCE_IPv6" ] && [ "$INSTANCE_IPv6" != "None" ]; then
    echo -e "${GREEN}✓ IPv6: $INSTANCE_IPv6${NC}"
    HAS_PUBLIC_ACCESS=true
fi

if [ "$HAS_PUBLIC_ACCESS" = false ]; then
    echo -e "${YELLOW}⚠ Instance has no public IPs (IPv6-only/private architecture)${NC}"
    echo -e "${YELLOW}⚠ Direct SSH access not available - use SSM or VPN${NC}"
fi

echo ""
echo -e "${GREEN}🎉 SSH access updated successfully!${NC}"
echo "Your IP: $CURRENT_IP"
echo "Security Group: $SECURITY_GROUP_NAME ($SECURITY_GROUP_ID)"
echo "Bastion Instance: $INSTANCE_ID"
echo "Private IP: $INSTANCE_PRIVATE_IP"

if [ -n "$INSTANCE_IPv4" ] && [ "$INSTANCE_IPv4" != "None" ]; then
    echo "Public IPv4: $INSTANCE_IPv4"
fi

if [ -n "$INSTANCE_IPv6" ] && [ "$INSTANCE_IPv6" != "None" ]; then
    echo "Public IPv6: $INSTANCE_IPv6"
fi

echo ""

# Provide connection instructions based on available access methods
if [ "$HAS_PUBLIC_ACCESS" = true ]; then
    echo "You can now SSH to your instance:"
    
    if [ -n "$INSTANCE_IPv4" ] && [ "$INSTANCE_IPv4" != "None" ]; then
        echo -e "${YELLOW}ssh ec2-user@${INSTANCE_IPv4}${NC}"
    fi
    
    if [ -n "$INSTANCE_IPv6" ] && [ "$INSTANCE_IPv6" != "None" ]; then
        # For SSH, IPv6 addresses don't need brackets
        echo -e "${YELLOW}ssh ec2-user@${INSTANCE_IPv6}${NC}"
    fi
else
    echo "🔒 Instance uses private/IPv6-only architecture"
    echo "Connect using AWS Systems Manager Session Manager:"
    echo -e "${YELLOW}aws ssm start-session --target $INSTANCE_ID --region $REGION${NC}"
    echo ""
    echo "Or connect via WireGuard VPN and use private IP:"
    echo -e "${YELLOW}ssh ec2-user@${INSTANCE_PRIVATE_IP}${NC}"
fi

echo ""
echo "💡 Run this script again if your IP changes"
