#!/bin/bash
set -e

if [ -d "/custom-maps" ]; then
    cp /custom-maps/*.pk3 /opt/xonotic/data/ 2>/dev/null || true
fi

envsubst < /opt/xonotic/server.cfg.template > /opt/xonotic/data/server.cfg.tmp

mv /opt/xonotic/data/server.cfg.tmp /opt/xonotic/data/server.cfg

echo "=== Xonotic Server Configuration ==="
echo "Hostname: ${SERVER_HOSTNAME}"
echo "Max Players: ${MAX_PLAYERS}"
echo "Custom Maps:${CUSTOM_MAPS}"
echo "===================================="

exec /opt/xonotic/xonotic-linux64-dedicated -dedicated
