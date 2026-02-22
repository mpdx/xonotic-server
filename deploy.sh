#!/bin/bash
set -euoa pipefail

if [ ! -f .env ]; then
    echo "Error: .env file not found. Copy .env.example and configure it."
    exit 1
fi

source .env

required_vars=(HETZNER_SSH_KEY HETZNER_TOKEN CLOUDFLARE_API_TOKEN CLOUDFLARE_ZONE_ID DOMAIN GIT_REPO_URL)
for var in "${required_vars[@]}"; do
    if [ -z "${!var:-}" ]; then
        echo "Error: $var is not set in .env"
        exit 1
    fi
done

# Default values
HETZNER_SERVER_TYPE="${HETZNER_SERVER_TYPE:-cx23}"
HETZNER_LOCATION="${HETZNER_LOCATION:-nbg1}"
HETZNER_IMAGE="${HETZNER_IMAGE:-debian-12}"
DNS_TTL="${DNS_TTL:-120}"
AUTO_DESTROY_HOURS="${AUTO_DESTROY_HOURS:-5}"
WEBHOOK_CALLBACK_URL="${WEBHOOK_CALLBACK_URL:-}"
WEBHOOK_SECRET="${WEBHOOK_SECRET:-}"

SERVER_NAME="xonotic-$(date +%s)"

echo "Generating cloud-init configuration..."
envsubst '${GIT_REPO_URL} ${SERVER_HOSTNAME} ${RCON_PASSWORD} ${GAME_PORT} ${MAP_SERVER_URL} ${HETZNER_TOKEN} ${AUTO_DESTROY_HOURS} ${WEBHOOK_CALLBACK_URL} ${WEBHOOK_SECRET} ${SERVER_NAME}' \
    < cloud-init.yaml.template > cloud-init.yaml

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

SERVER_IP=$(hcloud server ip "$SERVER_NAME")
echo "✓ Server created at $SERVER_IP"

echo "Updating Cloudflare DNS..."
RECORD_RESPONSE=$(curl -s -X GET \
    "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records?name=$DOMAIN" \
    -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
    -H "Content-Type: application/json")

RECORD_ID=$(echo "$RECORD_RESPONSE" | grep -o '"id":"[^"]*' | head -1 | cut -d'"' -f4)

if [ -n "$RECORD_ID" ]; then
    curl -s -X PUT \
        "https://api.cloudflare.com/client/v4/zones/$CLOUDFLARE_ZONE_ID/dns_records/$RECORD_ID" \
        -H "Authorization: Bearer $CLOUDFLARE_API_TOKEN" \
        -H "Content-Type: application/json" \
        --data "{\"type\":\"A\",\"name\":\"$DOMAIN\",\"content\":\"$SERVER_IP\",\"ttl\":$DNS_TTL,\"proxied\":false}" \
        > /dev/null
    echo "✓ DNS record updated"
else
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
echo "   This takes up couple of minutes to complete. Check status with:"
echo "   ssh root@$SERVER_IP 'tail -f /var/log/cloud-init-output.log'"
echo ""
echo "To destroy: hcloud server delete $SERVER_NAME"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
