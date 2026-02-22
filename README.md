# Xonotic Server Deployment

Xonotic game server with Hetzner cloud-init + Docker Compose.

## Quick Start

```bash
cp .env.example .env 
# edit .env according to your needs
bash deploy.sh
```

Check logs:
```bash
ssh root@<vps-ip>
cd /root/xonotic-server
docker-compose logs -f
```

Update and redeploy:
```bash
git pull
docker-compose down
docker-compose up -d --build
```