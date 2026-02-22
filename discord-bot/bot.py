import discord
from discord import app_commands
from discord.ext import commands
from fastapi import FastAPI, HTTPException
from pydantic import BaseModel
from dotenv import load_dotenv
import subprocess
import asyncio
import threading
import uvicorn
import json
import time
import re
import os

load_dotenv()

# Config
DOMAIN = os.environ["DOMAIN"]
DISCORD_TOKEN = os.environ["DISCORD_TOKEN"]
WEBHOOK_SECRET = os.environ["WEBHOOK_SECRET"]
DISCORD_WEBHOOK_URL = os.environ.get("DISCORD_WEBHOOK_URL")  # For "ready" notifications
REPO_PATH = os.environ.get("REPO_PATH", "/root/xonotic-server")
STATE_FILE = "server_state.json"

# ============ State Management ============


def load_state():
    if os.path.exists(STATE_FILE):
        return json.load(open(STATE_FILE))
    return None


def save_state(state):
    json.dump(state, open(STATE_FILE, "w"))


def clear_state():
    if os.path.exists(STATE_FILE):
        os.remove(STATE_FILE)


# ============ FastAPI Webhook Server ============

api = FastAPI()


class ReadyRequest(BaseModel):
    token: str
    server_name: str = ""


@api.post("/ready")
async def ready(req: ReadyRequest):
    """Called by Xonotic server when game is listening"""
    if req.token != WEBHOOK_SECRET:
        raise HTTPException(403, "Invalid token")

    state = load_state()
    if state and state.get("server_name") == req.server_name:
        state["ready"] = True
        save_state(state)

        # Notify Discord channel via webhook
        if DISCORD_WEBHOOK_URL:
            import httpx

            async with httpx.AsyncClient() as client:
                await client.post(
                    DISCORD_WEBHOOK_URL,
                    json={
                        "embeds": [
                            {
                                "title": "Xonotic Server Ready!",
                                "description": "Server is now accepting connections",
                                "color": 0x00FF00,
                                "fields": [
                                    {
                                        "name": "Connect",
                                        "value": f"`{DOMAIN}:26000`",
                                        "inline": False,
                                    }
                                ],
                            }
                        ]
                    },
                )

    return {"status": "ok"}


def run_api():
    """Run FastAPI in a separate thread"""
    uvicorn.run(api, host="0.0.0.0", port=8000, log_level="warning")


# ============ Discord Bot ============


class XonoticBot(commands.Bot):
    def __init__(self):
        intents = discord.Intents.default()
        super().__init__(command_prefix="!", intents=intents)

    async def setup_hook(self):
        await self.tree.sync()


bot = XonoticBot()


@bot.tree.command(name="xonotic-create", description="Create a Xonotic server")
@app_commands.describe(hours="Auto-destroy after N hours (default: 5, max: 5)")
@app_commands.checks.cooldown(1, 600)  # 10 min global cooldown
async def create_server(interaction: discord.Interaction, hours: int = 5):
    await interaction.response.defer()

    # Cap at 5 hours max, minimum 1 hour
    hours = max(1, min(hours, 5))

    state = load_state()
    if state:
        await interaction.followup.send(
            f"A server is already running: `{state['server_name']}`"
        )
        return

    # Run deploy.sh
    env = os.environ.copy()
    env["AUTO_DESTROY_HOURS"] = str(hours)

    result = subprocess.run(
        ["./deploy.sh"], capture_output=True, text=True, cwd=REPO_PATH, env=env
    )

    if result.returncode != 0:
        await interaction.followup.send(
            f"Deploy failed:\n```{result.stderr[:1000]}```"
        )
        return

    # Parse output
    output = result.stdout
    name_match = re.search(r"Server Name:\s+(\S+)", output)
    ip_match = re.search(r"IP Address:\s+(\S+)", output)

    server_name = name_match.group(1) if name_match else "unknown"
    ip = ip_match.group(1) if ip_match else "unknown"

    state = {
        "server_name": server_name,
        "ip": ip,
        "hours": hours,
        "created_at": int(time.time()),
        "destroy_at": int(time.time()) + (hours * 3600),
        "ready": False,
    }
    save_state(state)

    embed = discord.Embed(
        title="Xonotic Server Starting...", color=discord.Color.yellow()
    )
    embed.add_field(name="Connect", value=f"`{DOMAIN}:26000`", inline=False)
    embed.add_field(name="IP", value=ip, inline=True)
    embed.add_field(name="Server Name", value=server_name, inline=True)
    embed.set_footer(
        text=f"Auto-destroy in {hours}h. You'll be notified when server is ready."
    )

    await interaction.followup.send(embed=embed)


@bot.tree.command(name="xonotic-destroy", description="Destroy the Xonotic server")
@app_commands.checks.cooldown(1, 600)
async def destroy_server(interaction: discord.Interaction):
    await interaction.response.defer()

    state = load_state()
    if not state:
        await interaction.followup.send("No server is running.")
        return

    result = subprocess.run(
        ["hcloud", "server", "delete", state["server_name"]],
        capture_output=True,
        text=True,
    )

    if result.returncode != 0:
        await interaction.followup.send(
            f"Failed to destroy server:\n```{result.stderr[:500]}```"
        )
        return

    clear_state()

    embed = discord.Embed(
        title="Server Destroyed",
        description=f"Server `{state['server_name']}` has been destroyed.",
        color=discord.Color.red(),
    )
    await interaction.followup.send(embed=embed)


async def query_xonotic_server(ip: str, port: int = 26000) -> dict | None:
    """Query Xonotic server for status using DarkPlaces protocol"""
    import socket

    def _query():
        try:
            sock = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
            sock.settimeout(2)
            # DarkPlaces/Quake3 status query
            sock.sendto(b"\xff\xff\xff\xffgetstatus\n", (ip, port))
            data, _ = sock.recvfrom(4096)
            sock.close()

            # Parse response: \xff\xff\xff\xffstatusResponse\n\\key\\value\\key\\value...\nplayer1\nplayer2
            response = data.decode("utf-8", errors="ignore")
            lines = response.split("\n")

            if len(lines) < 2:
                return None

            # Parse server info (line 1)
            info_line = lines[1]
            info = {}
            parts = info_line.split("\\")[1:]  # Skip first empty element
            for i in range(0, len(parts) - 1, 2):
                info[parts[i]] = parts[i + 1]

            # Parse players (remaining lines)
            players = []
            for line in lines[2:]:
                if line.strip():
                    # Format: "score ping name"
                    players.append(line.strip())

            return {
                "map": info.get("mapname", "unknown"),
                "players": len(players),
                "max_players": info.get("sv_maxclients", "?"),
                "hostname": info.get("hostname", "Xonotic Server"),
            }
        except Exception:
            return None

    return await asyncio.to_thread(_query)


@bot.tree.command(name="xonotic-status", description="Check server status")
async def server_status(interaction: discord.Interaction):
    await interaction.response.defer()

    state = load_state()

    if not state:
        embed = discord.Embed(title="No Server Running", color=discord.Color.greyple())
        await interaction.followup.send(embed=embed)
        return

    status = "Ready" if state.get("ready") else "Starting..."
    color = discord.Color.green() if state.get("ready") else discord.Color.yellow()
    embed = discord.Embed(title=f"Server {status}", color=color)
    embed.add_field(name="Connect", value=f"`{DOMAIN}:26000`", inline=False)
    embed.add_field(name="IP", value=state["ip"], inline=True)
    embed.add_field(name="Auto-destroy", value=f"<t:{state['destroy_at']}:R>", inline=True)

    # Query live server info if ready
    if state.get("ready"):
        server_info = await query_xonotic_server(state["ip"])
        if server_info:
            embed.add_field(name="Map", value=server_info["map"], inline=True)
            embed.add_field(
                name="Players",
                value=f"{server_info['players']}/{server_info['max_players']}",
                inline=True,
            )

    await interaction.followup.send(embed=embed)


@create_server.error
@destroy_server.error
async def on_cooldown_error(interaction: discord.Interaction, error):
    if isinstance(error, app_commands.CommandOnCooldown):
        await interaction.response.send_message(
            f"Please wait {int(error.retry_after)}s before using this command again.",
            ephemeral=True,
        )
    else:
        raise error


# ============ Main ============

if __name__ == "__main__":
    # Start webhook server in background thread
    api_thread = threading.Thread(target=run_api, daemon=True)
    api_thread.start()

    # Run Discord bot (blocking)
    bot.run(DISCORD_TOKEN)
