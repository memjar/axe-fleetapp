#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# AXE Fleet Notification Daemon v1.0
# Sovereign NTFY — Native macOS notifications for all AXE services
# No external dependencies. No API spend. Pure local iron.
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${APP_DIR}/config/fleet-config.json"
STATE_DIR="${APP_DIR}/logs/state"
LOG_FILE="${APP_DIR}/logs/axe-fleet-notify.log"
COOLDOWN_DIR="${APP_DIR}/logs/cooldown"

mkdir -p "$STATE_DIR" "$COOLDOWN_DIR" "$(dirname "$LOG_FILE")"

# ─── Logging ──────────────────────────────────────────────────
log() {
    local level="$1"; shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$LOG_FILE"
}

log "INFO" "═══ AXE Fleet Notify starting ═══"
log "INFO" "Config: $CONFIG_FILE"
log "INFO" "State: $STATE_DIR"

# ─── Config parsing (jq-free for zero deps) ──────────────────
# We use python3 -c for JSON parsing since it's on every Mac
parse_json() {
    python3 -c "
import json, sys
with open('$CONFIG_FILE') as f:
    cfg = json.load(f)
$1
" 2>/dev/null
}

POLL_INTERVAL=$(parse_json "print(cfg.get('poll_interval_seconds', 30))")
COOLDOWN_SECONDS=$(parse_json "print(cfg.get('notification_cooldown_seconds', 300))")

log "INFO" "Poll interval: ${POLL_INTERVAL}s | Cooldown: ${COOLDOWN_SECONDS}s"

# ─── Notification Engine ──────────────────────────────────────
notify() {
    local title="$1"
    local message="$2"
    local sound="${3:-Glass}"
    local key="$4"

    # Cooldown check — don't spam the same alert
    local cooldown_file="${COOLDOWN_DIR}/${key}"
    if [[ -f "$cooldown_file" ]]; then
        local last_fire=$(cat "$cooldown_file")
        local now=$(date +%s)
        local elapsed=$((now - last_fire))
        if [[ $elapsed -lt $COOLDOWN_SECONDS ]]; then
            return 0
        fi
    fi

    # Fire native macOS notification
    osascript -e "display notification \"${message}\" with title \"${title}\" sound name \"${sound}\"" 2>/dev/null || true

    # Record cooldown
    date +%s > "$cooldown_file"

    log "NOTIFY" "[$sound] $title — $message"
}

# ─── State Management ─────────────────────────────────────────
get_state() {
    local key="$1"
    local state_file="${STATE_DIR}/${key}"
    if [[ -f "$state_file" ]]; then
        cat "$state_file"
    else
        echo "unknown"
    fi
}

set_state() {
    local key="$1"
    local value="$2"
    echo "$value" > "${STATE_DIR}/${key}"
}

# ─── Check: Ping a host ──────────────────────────────────────
check_ping() {
    local ip="$1"
    if ping -c 1 -W 2 "$ip" &>/dev/null; then
        echo "online"
    else
        echo "offline"
    fi
}

# ─── Check: TCP port ─────────────────────────────────────────
check_tcp() {
    local ip="$1"
    local port="$2"
    if nc -z -w 3 "$ip" "$port" &>/dev/null; then
        echo "up"
    else
        echo "down"
    fi
}

# ─── Check: HTTP endpoint ────────────────────────────────────
check_http() {
    local url="$1"
    local status
    status=$(curl -s -o /dev/null -w "%{http_code}" --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || echo "000")
    if [[ "$status" -ge 200 && "$status" -lt 400 ]]; then
        echo "up"
    else
        echo "down"
    fi
}

# ─── Check: WireGuard mesh ───────────────────────────────────
check_wireguard() {
    local peer_ip="$1"
    if ping -c 1 -W 2 "$peer_ip" &>/dev/null; then
        echo "up"
    else
        echo "down"
    fi
}

# ─── Monitor: Fleet Machines ─────────────────────────────────
monitor_fleet() {
    parse_json "
import json
fleet = cfg.get('fleet', {})
for key, machine in fleet.items():
    name = machine['name']
    ip = machine['ip']
    tier = machine.get('tier', 3)
    do_ping = machine.get('ping', True)
    services = machine.get('services', [])
    svc_json = json.dumps(services)
    print(f'{key}|{name}|{ip}|{tier}|{do_ping}|{svc_json}')
" | while IFS='|' read -r key name ip tier do_ping services_json; do

        # Ping check
        if [[ "$do_ping" == "True" ]]; then
            local status
            status=$(check_ping "$ip")
            local prev
            prev=$(get_state "fleet_${key}_ping")

            if [[ "$status" != "$prev" ]]; then
                set_state "fleet_${key}_ping" "$status"
                if [[ "$status" == "online" ]]; then
                    local sound="Hero"
                    [[ "$tier" -gt 2 ]] && sound="Pop"
                    notify "⚡ AXE Fleet" "${name} is ONLINE" "$sound" "fleet_${key}_ping"
                else
                    local sound="Basso"
                    [[ "$tier" -gt 2 ]] && sound="Purr"
                    notify "🔴 AXE Fleet" "${name} is OFFLINE" "$sound" "fleet_${key}_ping"
                fi
            fi

            # Only check services if host is online
            if [[ "$status" == "online" ]]; then
                echo "$services_json" | python3 -c "
import json, sys
services = json.load(sys.stdin)
for svc in services:
    name = svc['name']
    port = svc['port']
    proto = svc.get('protocol', 'tcp')
    path = svc.get('path', '/')
    print(f'{name}|{port}|{proto}|{path}')
" 2>/dev/null | while IFS='|' read -r svc_name svc_port svc_proto svc_path; do
                    local svc_status
                    if [[ "$svc_proto" == "http" ]]; then
                        svc_status=$(check_http "http://${ip}:${svc_port}${svc_path}")
                    else
                        svc_status=$(check_tcp "$ip" "$svc_port")
                    fi

                    local svc_prev
                    svc_prev=$(get_state "fleet_${key}_svc_${svc_name// /_}")

                    if [[ "$svc_status" != "$svc_prev" ]]; then
                        set_state "fleet_${key}_svc_${svc_name// /_}" "$svc_status"
                        if [[ "$svc_status" == "up" ]]; then
                            notify "✅ ${name}" "${svc_name} is UP (port ${svc_port})" "Pop" "fleet_${key}_${svc_name// /_}"
                        else
                            notify "⚠️ ${name}" "${svc_name} is DOWN (port ${svc_port})" "Purr" "fleet_${key}_${svc_name// /_}"
                        fi
                    fi
                done
            fi
        else
            # Local machine — just check services
            echo "$services_json" | python3 -c "
import json, sys
services = json.load(sys.stdin)
for svc in services:
    name = svc['name']
    port = svc['port']
    proto = svc.get('protocol', 'tcp')
    path = svc.get('path', '/')
    print(f'{name}|{port}|{proto}|{path}')
" 2>/dev/null | while IFS='|' read -r svc_name svc_port svc_proto svc_path; do
                local svc_status
                if [[ "$svc_proto" == "http" ]]; then
                    svc_status=$(check_http "http://${ip}:${svc_port}${svc_path}")
                else
                    svc_status=$(check_tcp "$ip" "$svc_port")
                fi

                local svc_prev
                svc_prev=$(get_state "fleet_${key}_svc_${svc_name// /_}")

                if [[ "$svc_status" != "$svc_prev" ]]; then
                    set_state "fleet_${key}_svc_${svc_name// /_}" "$svc_status"
                    if [[ "$svc_status" == "up" ]]; then
                        notify "✅ JL2 Local" "${svc_name} is UP (port ${svc_port})" "Pop" "local_${svc_name// /_}"
                    else
                        notify "⚠️ JL2 Local" "${svc_name} is DOWN (port ${svc_port})" "Purr" "local_${svc_name// /_}"
                    fi
                fi
            done
        fi
    done
}

# ─── Monitor: Web Services ────────────────────────────────────
monitor_web() {
    parse_json "
for key, svc in cfg.get('web_services', {}).items():
    name = svc['name']
    url = svc['url']
    tier = svc.get('tier', 2)
    print(f'{key}|{name}|{url}|{tier}')
" | while IFS='|' read -r key name url tier; do
        local status
        status=$(check_http "$url")
        local prev
        prev=$(get_state "web_${key}")

        if [[ "$status" != "$prev" ]]; then
            set_state "web_${key}" "$status"
            if [[ "$status" == "up" ]]; then
                local sound="Pop"
                [[ "$tier" -eq 1 ]] && sound="Hero"
                notify "🌐 AXE Web" "${name} is UP" "$sound" "web_${key}"
            else
                local sound="Purr"
                [[ "$tier" -eq 1 ]] && sound="Basso"
                notify "🔴 AXE Web" "${name} is DOWN — ${url}" "$sound" "web_${key}"
            fi
        fi
    done
}

# ─── Monitor: WireGuard Mesh ─────────────────────────────────
monitor_wireguard() {
    local wg_enabled
    wg_enabled=$(parse_json "print(cfg.get('wireguard', {}).get('enabled', False))")

    if [[ "$wg_enabled" != "True" ]]; then
        return 0
    fi

    parse_json "
peers = cfg.get('wireguard', {}).get('peers', {})
for key, ip in peers.items():
    print(f'{key}|{ip}')
" | while IFS='|' read -r key ip; do
        local status
        status=$(check_wireguard "$ip")
        local prev
        prev=$(get_state "wg_${key}")

        if [[ "$status" != "$prev" ]]; then
            set_state "wg_${key}" "$status"
            if [[ "$status" == "up" ]]; then
                notify "🔒 WireGuard" "Mesh peer ${key} (${ip}) is UP" "Pop" "wg_${key}"
            else
                notify "🔓 WireGuard" "Mesh peer ${key} (${ip}) is DOWN" "Basso" "wg_${key}"
            fi
        fi
    done
}

# ─── Monitor: Droplets ────────────────────────────────────────
monitor_droplets() {
    parse_json "
import json
for key, drop in cfg.get('droplets', {}).items():
    name = drop['name']
    ip = drop['ip']
    tier = drop.get('tier', 2)
    services = json.dumps(drop.get('services', []))
    print(f'{key}|{name}|{ip}|{tier}|{services}')
" | while IFS='|' read -r key name ip tier services_json; do
        # Ping droplet
        local status
        status=$(check_ping "$ip")
        local prev
        prev=$(get_state "droplet_${key}_ping")

        if [[ "$status" != "$prev" ]]; then
            set_state "droplet_${key}_ping" "$status"
            if [[ "$status" == "online" ]]; then
                notify "☁️ Droplet" "${name} (${ip}) is ONLINE" "Hero" "droplet_${key}_ping"
            else
                notify "🔴 Droplet" "${name} (${ip}) is OFFLINE" "Basso" "droplet_${key}_ping"
            fi
        fi

        # Check services if online
        if [[ "$status" == "online" ]]; then
            echo "$services_json" | python3 -c "
import json, sys
services = json.load(sys.stdin)
for svc in services:
    name = svc['name']
    port = svc['port']
    proto = svc.get('protocol', 'tcp')
    path = svc.get('path', '/')
    print(f'{name}|{port}|{proto}|{path}')
" 2>/dev/null | while IFS='|' read -r svc_name svc_port svc_proto svc_path; do
                local svc_status
                if [[ "$svc_proto" == "http" ]]; then
                    svc_status=$(check_http "http://${ip}:${svc_port}${svc_path}")
                elif [[ "$svc_port" == "443" ]]; then
                    svc_status=$(check_tcp "$ip" "$svc_port")
                else
                    svc_status=$(check_tcp "$ip" "$svc_port")
                fi

                local svc_prev
                svc_prev=$(get_state "droplet_${key}_svc_${svc_name// /_}")

                if [[ "$svc_status" != "$svc_prev" ]]; then
                    set_state "droplet_${key}_svc_${svc_name// /_}" "$svc_status"
                    if [[ "$svc_status" == "up" ]]; then
                        notify "☁️ ${name}" "${svc_name} is UP" "Pop" "droplet_${key}_${svc_name// /_}"
                    else
                        notify "⚠️ ${name}" "${svc_name} is DOWN" "Purr" "droplet_${key}_${svc_name// /_}"
                    fi
                fi
            done
        fi
    done
}

# ─── Status CLI ───────────────────────────────────────────────
if [[ "${1:-}" == "status" ]]; then
    echo "═══ AXE Fleet Status ═══"
    echo ""
    echo "Fleet Machines:"
    for f in "${STATE_DIR}"/fleet_*_ping; do
        [[ -f "$f" ]] || continue
        key=$(basename "$f" | sed 's/fleet_//;s/_ping//')
        status=$(cat "$f")
        icon="🔴"
        [[ "$status" == "online" ]] && icon="✅"
        echo "  $icon $key: $status"
    done
    echo ""
    echo "Web Services:"
    for f in "${STATE_DIR}"/web_*; do
        [[ -f "$f" ]] || continue
        key=$(basename "$f" | sed 's/web_//')
        status=$(cat "$f")
        icon="🔴"
        [[ "$status" == "up" ]] && icon="✅"
        echo "  $icon $key: $status"
    done
    echo ""
    echo "WireGuard Mesh:"
    for f in "${STATE_DIR}"/wg_*; do
        [[ -f "$f" ]] || continue
        key=$(basename "$f" | sed 's/wg_//')
        status=$(cat "$f")
        icon="🔴"
        [[ "$status" == "up" ]] && icon="🔒"
        echo "  $icon $key: $status"
    done
    echo ""
    echo "Droplets:"
    for f in "${STATE_DIR}"/droplet_*_ping; do
        [[ -f "$f" ]] || continue
        key=$(basename "$f" | sed 's/droplet_//;s/_ping//')
        status=$(cat "$f")
        icon="🔴"
        [[ "$status" == "online" ]] && icon="☁️"
        echo "  $icon $key: $status"
    done
    echo ""
    echo "Last log entries:"
    tail -5 "$LOG_FILE" 2>/dev/null || echo "  (no logs yet)"
    exit 0
fi

# ─── Main Loop ────────────────────────────────────────────────
log "INFO" "Starting monitoring loop (${POLL_INTERVAL}s interval)"
notify "🪓 AXE Fleet" "Fleet Notify daemon started — monitoring all services" "Glass" "daemon_start"

# Trap for clean shutdown
trap 'log "INFO" "═══ AXE Fleet Notify stopping ═══"; notify "🪓 AXE Fleet" "Fleet Notify daemon stopped" "Basso" "daemon_stop"; exit 0' SIGTERM SIGINT

while true; do
    monitor_fleet
    monitor_web
    monitor_wireguard
    monitor_droplets
    sleep "$POLL_INTERVAL"
done
