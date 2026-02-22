# Xonotic Server Deployment

Xonotic game server with Hetzner cloud-init + Docker Compose. 
Includes Discord bot for server management.

## Prerequisites

- Hetzner Cloud account (and hcloud cli installed)
- Domain name with Cloudflare DNS
- Discord bot with `bot` and `applications.commands` scopes

## Quick Start

```bash
cp .env.example .env
vim .env # update according to your needs
bash deploy.sh
```

Check logs:
```bash
ssh root@<vps-ip>
cd /root/xonotic-server
docker-compose logs -f
```

## Discord Bot

Manage Xonotic servers from Discord with slash commands:

| Command | Description |
|---------|-------------|
| `/xonotic-create` | Create a server (optionally pass parameter 1-5 hours for auto-destroy, 5 is default) |
| `/xonotic-destroy` | Destroy the running server |
| `/xonotic-status` | Check server status, map, and player count |

### Bot Setup

1. Create Discord bot at https://discord.com/developers/applications
2. Invite bot with `bot` and `applications.commands` scopes to your channel
3. Install on your VPS:

```bash
git clone https://github.com/yourusername/xonotic-server.git /root/xonotic-server && cd /root/xonotic-server/discord-bot

python3 -m venv .venv && source .venv/bin/activate
pip install -r requirements.txt

cp .env.example .env
vim .env  # update with your tokens
```

4. Run as systemd service:

```bash
cat > /etc/systemd/system/xonotic-bot.service << 'EOF'
[Unit]
Description=Xonotic Discord Bot
After=network.target

[Service]
Type=simple
User=root
WorkingDirectory=/root/xonotic-server/discord-bot
EnvironmentFile=/root/xonotic-server/discord-bot/.env
ExecStart=/root/xonotic-server/discord-bot/.venv/bin/python bot.py
Restart=always
RestartSec=10

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable --now xonotic-bot
```