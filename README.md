# Xonotic Server Deployment

Xonotic game server with cloud-init + Docker Compose.

## Quick Start

```bash
vim cloud-init.yaml
cp .env.example .env && vim .env
chmod +x deploy.sh && ./deploy.sh
```

On VPS:
```bash
cd /root/xonotic-server
git pull
docker-compose restart
```

Check logs:
```bash
ssh root@<vps-ip>
cd /root/xonotic-server
docker-compose logs -f
```

Restart:
```bash
docker-compose restart
```

Update and redeploy:
```bash
git pull
docker-compose down
docker-compose up -d --build
```