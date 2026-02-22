#!/bin/bash
set -e

# Generate server.cfg from environment variables at runtime
cat > /opt/xonotic/data/server.cfg <<EOF
hostname "${SERVER_HOSTNAME}"
rcon_password "${RCON_PASSWORD}"
maxplayers ${MAX_PLAYERS}
port ${GAME_PORT}
sv_curl_defaulturl "${MAP_SERVER_URL}"
sv_public -1
sv_status_privacy 1
g_maxplayers ${MAX_PLAYERS}
EOF

# Start Xonotic dedicated server
exec /opt/xonotic/xonotic-linux-dedicated -dedicated
