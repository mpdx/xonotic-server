#!/bin/bash
set -euo pipefail

# Load environment variables
if [ ! -f .env ]; then
    echo "Error: .env file not found. Copy .env.example and configure it."
    exit 1
fi

source .env

# Validate required variables
required_vars=(HETZNER_SSH_KEY CLOUDFLARE_API_TOKEN CLOUDFLARE_ZONE_ID DOMAIN GIT_REPO_URL)
for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "Error: $var is not set in .env"
        exit 1
    fi
done

# Default values
HETZNER_SERVER_TYPE="${HETZNER_SERVER_TYPE:-cx11}"
HETZNER_LOCATION="${HETZNER_LOCATION:-nbg1}"
HETZNER_IMAGE="${HETZNER_IMAGE:-debian-12}"
DNS_TTL="${DNS_TTL:-120}"

# Generate server name
SERVER_NAME="xonotic-$(date +%s)"

echo "Creating Hetzner VPS..."
hcloud server create \
    --name "$SERVER_NAME" \
    --type "$HETZNER_SERVER_TYPE" \
    --image "$HETZNER_IMAGE" \
    --location "$HETZNER_LOCATION" \
    --ssh-key "$HETZNER_SSH_KEY" \
    --user-data-from-file cloud-init.yaml

echo "Waiting for server to start..."
sleep 5

# Get server IP
SERVER_IP=$(hcloud server ip "$SERVER_NAME")
echo "✓ Server created at $SERVER_IP"

# Update Cloudflare DNS
echo "Updating Cloudflare DNS..."

# Get existing DNS record ID (if exists)
RECORD_RESPONSE=$(curl -s -X GET \
    "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?name=$DOMAIN" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json")

RECORD_ID=$(echo "$RECORD_RESPONSE" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)

if [ -n "$RECORD_ID" ]; then
    # Update existing record
    curl -s -X PUT \
        "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$RECORD_ID" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$DOMAIN\",\"content\":\"$SERVER_IP\",\"ttl\":$DNS_TTL,\"proxied\":false}" \
        > /dev/null
    echo "✓ DNS record updated"
else
    # Create new record
    curl -s -X POST \
        "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$DOMAIN\",\"content\":\"$SERVER_IP\",\"ttl\":$DNS_TTL,\"proxied\":false}" \
        > /dev/null
    echo "✓ DNS record created"
fi

echo ""
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Xonotic Server Deployment Started"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "Server Name:  $SERVER_NAME"
echo "IP Address:   $SERVER_IP"
echo "Game Server:  $DOMAIN:26000"
echo "Map Server:   http://$DOMAIN:8080/maps/"
echo "SSH Access:   ssh root@$SERVER_IP"
echo ""
echo "Cloud-init is provisioning the server..."
echo "   This takes up to 3 minutes. Check status with:"
echo "   ssh root@$SERVER_IP 'tail -f /var/log/cloud-init-output.log'"
echo ""
echo "To destroy: hcloud server delete $SERVER_NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
