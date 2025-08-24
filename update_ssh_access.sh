#!/bin/bash
# SSH Access Updater Script
# Updates EC2 security group to allow SSH access from current public IP only,
# and prints out the current bastion instance IP + SSH command.

set -euo pipefail

# --- Configuration ---
REGION="eu-west-1"
ASG_NAME="tf-asg"
SECURITY_GROUP_NAME="sandbox-eu-bastion-sg"
ENV_FILE=".env"

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

echo -n "Looking up public IPs of $INSTANCE_ID... "

INSTANCE_IPv4="$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].PublicIpAddress' \
    --output text 2>/dev/null || true)"

INSTANCE_IPv6="$(aws ec2 describe-instances \
    --region "$REGION" \
    --instance-ids "$INSTANCE_ID" \
    --query 'Reservations[0].Instances[0].NetworkInterfaces[0].Ipv6Addresses[0].Ipv6Address' \
    --output text 2>/dev/null || true)"

if { [ -z "$INSTANCE_IPv4" ] || [ "$INSTANCE_IPv4" = "None" ]; } \
   && { [ -z "$INSTANCE_IPv6" ] || [ "$INSTANCE_IPv6" = "None" ]; }; then
    echo -e "${RED}✗ Instance has no public IPs${NC}"
    exit 1
fi

[ -n "$INSTANCE_IPv4" ] && [ "$INSTANCE_IPv4" != "None" ] && \
  echo -e "${GREEN}✓ IPv4: $INSTANCE_IPv4${NC}"

[ -n "$INSTANCE_IPv6" ] && [ "$INSTANCE_IPv6" != "None" ] && \
  echo -e "${GREEN}✓ IPv6: $INSTANCE_IPv6${NC}"

echo ""
echo -e "${GREEN}🎉 SSH access updated successfully!${NC}"
echo "Your IP: $CURRENT_IP"
echo "Security Group: $SECURITY_GROUP_NAME ($SECURITY_GROUP_ID)"
echo "Bastion Instance: $INSTANCE_ID"

if [ -n "$INSTANCE_IPv4" ] && [ "$INSTANCE_IPv4" != "None" ]; then
    echo "Public IPv4: $INSTANCE_IPv4"
fi

if [ -n "$INSTANCE_IPv6" ] && [ "$INSTANCE_IPv6" != "None" ]; then
    echo "Public IPv6: $INSTANCE_IPv6"
fi

echo ""
echo "You can now SSH to your instance:"

if [ -n "$INSTANCE_IPv4" ] && [ "$INSTANCE_IPv4" != "None" ]; then
    echo -e "${YELLOW}ssh ec2-user@${INSTANCE_IPv4}${NC}"
fi

if [ -n "$INSTANCE_IPv6" ] && [ "$INSTANCE_IPv6" != "None" ]; then
    # IPv6 literal addresses in ssh/scp must be wrapped in []
    echo -e "${YELLOW}ssh ec2-user@${INSTANCE_IPv6}${NC}"
fi

echo ""
echo "💡 Run this script again if your IP changes"
