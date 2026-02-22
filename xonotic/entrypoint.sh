#!/bin/bash
set -e

envsubst < /opt/xonotic/server.cfg.template > /opt/xonotic/data/server.cfg.tmp

CUSTOM_MAPS=""
if [ -d "/opt/xonotic/data/data" ] && [ "$(ls -A /opt/xonotic/data/data/*.pk3 2>/dev/null)" ]; then
    for map_file in /opt/xonotic/data/data/*.pk3; do
        if [ -f "$map_file" ]; then
            map_name=$(basename "$map_file" .pk3)
            CUSTOM_MAPS="$CUSTOM_MAPS $map_name"
        fi
    done
fi

if [ -n "$CUSTOM_MAPS" ]; then
    sed -i "/^g_maplist/s/\"$/ $CUSTOM_MAPS\"/" /opt/xonotic/data/server.cfg.tmp
fi

mv /opt/xonotic/data/server.cfg.tmp /opt/xonotic/data/server.cfg

echo "=== Xonotic Server Configuration ==="
echo "Hostname: ${SERVER_HOSTNAME}"
echo "Max Players: ${MAX_PLAYERS}"
echo "Custom Maps:${CUSTOM_MAPS}"
echo "===================================="

exec /opt/xonotic/xonotic-linux64-dedicated -dedicated
