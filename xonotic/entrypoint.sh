#!/bin/bash
set -e

if [ -d "/custom-maps" ]; then
    cp /custom-maps/*.pk3 /opt/xonotic/data/ 2>/dev/null || true
fi

envsubst < /opt/xonotic/server.cfg.template > /opt/xonotic/data/server.cfg

exec /opt/xonotic/xonotic-linux64-dedicated -dedicated
