# 🪓 AXE Fleet Notify

**Sovereign fleet monitoring with native macOS notifications. Like NTFY, but running on your own iron.**

Zero external dependencies. Zero API spend. Pure local fleet intelligence.

## What It Monitors

| Tier | Category | Examples |
|------|----------|---------|
| 1 | **Critical Infrastructure** | AXIOM, axe.observer, AuthGate, fleet machines |
| 2 | **Fleet Services** | llama-server, Ollama, Qdrant, ops_centre, chat_centre |
| 3 | **Peripheral Nodes** | Ghost, Reaper, Lewis MBP |
| 4 | **Web Deployments** | Klaus, Halo, Vault, Meridian, MCP Hub |
| 5 | **Droplet Infrastructure** | DO axiom-worker1, axe-gate |

Plus: WireGuard mesh connectivity, local daemons (Partner Gateway), and service ports.

## Quick Start

```bash
# Clone and install
git clone https://github.com/memjar/axe-fleetapp.git
cd axe-fleetapp
./install.sh

# Check status
axe-fleet status

# Watch live events
tail -f logs/axe-fleet-notify.log
```

## How It Works

1. **Polls** every 30s (configurable) across all fleet machines, web services, WireGuard mesh, and droplets
2. **Detects state changes** — only fires notifications on transitions (online→offline, not every cycle)
3. **Native macOS notifications** via `osascript` with tiered sounds:
   - 🔴 Critical down: **Basso** (deep alert)
   - ✅ Critical up: **Hero** (triumphant)
   - ⚠️ Warning down: **Purr** (gentle nudge)
   - ✅ Warning up: **Pop** (quick confirmation)
4. **Cooldown system** — won't spam the same alert within 5 minutes (configurable)
5. **Flap detection** — machines that bounce online/offline rapidly get suppressed after 3 flaps

## Architecture

```
axe-fleetapp/
├── config/
│   └── fleet-config.json    # All services, IPs, ports, tiers
├── scripts/
│   └── axe-fleet-notify.sh  # Main daemon (bash + python3 JSON parsing)
├── launchagents/
│   └── com.axe.fleet-notify.plist  # macOS LaunchAgent template
├── logs/
│   ├── state/               # Current state of each monitor target
│   ├── cooldown/            # Notification cooldown timestamps
│   └── axe-fleet-notify.log # Event log
├── install.sh               # One-command install
├── uninstall.sh             # Clean removal
└── README.md
```

## Configuration

Edit `config/fleet-config.json` to add/remove services:

```json
{
  "fleet": {
    "my_machine": {
      "name": "My Machine",
      "ip": "192.168.1.100",
      "tier": 2,
      "ping": true,
      "services": [
        { "name": "SSH", "port": 22, "protocol": "tcp" },
        { "name": "My API", "port": 8080, "protocol": "http", "path": "/health" }
      ]
    }
  }
}
```

### Tiers

- **Tier 1**: Critical — loud alerts (Basso/Hero sounds)
- **Tier 2**: Important — moderate alerts (Purr/Pop sounds)  
- **Tier 3**: Peripheral — gentle alerts (Glass sound)

## CLI

```bash
axe-fleet status       # Show all monitored targets and their state
axe-fleet              # Run daemon in foreground (for testing)
```

## Daemon Management

```bash
# Start
launchctl load ~/Library/LaunchAgents/com.axe.fleet-notify.plist

# Stop
launchctl unload ~/Library/LaunchAgents/com.axe.fleet-notify.plist

# Restart
launchctl unload ~/Library/LaunchAgents/com.axe.fleet-notify.plist
launchctl load ~/Library/LaunchAgents/com.axe.fleet-notify.plist

# Check if running
launchctl list | grep fleet-notify
```

## Requirements

- macOS (any version with Notification Center)
- python3 (ships with macOS)
- curl (ships with macOS)
- No pip packages. No brew installs. No API keys.

## Part of the AXE Ecosystem

Built by [aXe Technologies](https://axetechnologies.ca). Sovereign AI infrastructure for the sovereign mind.

- [AXIOM](https://axiom.com.vc) — AI Portal
- [AXE Observer](https://axe.observer) — Fleet Operations HQ
- [AuthGate](https://authgate.cloud) — Push Authentication
- [Halo](https://halo.axe.observer) — Knowledge Graph
