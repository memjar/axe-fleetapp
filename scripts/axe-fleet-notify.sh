#!/bin/bash
# ═══════════════════════════════════════════════════════════════
# AXE Fleet Notification Daemon v2.0
# Sovereign NTFY — Native macOS notifications for all AXE services
# 
# v2.0 Features:
#   - Flap detection (suppresses notification storms)
#   - axe.observer data tower reporting
#   - Structured event log for AI/ML training
#   - Trend tracking and anomaly detection
#   - Response time monitoring for HTTP services
#
# Zero external dependencies. Zero API spend. Pure local iron.
# ═══════════════════════════════════════════════════════════════

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "$0")" && pwd)"
APP_DIR="$(dirname "$SCRIPT_DIR")"
CONFIG_FILE="${APP_DIR}/config/fleet-config.json"
STATE_DIR="${APP_DIR}/logs/state"
LOG_FILE="${APP_DIR}/logs/axe-fleet-notify.log"
EVENTS_LOG="${APP_DIR}/logs/events.jsonl"
COOLDOWN_DIR="${APP_DIR}/logs/cooldown"
FLAP_DIR="${APP_DIR}/logs/flap"
METRICS_DIR="${APP_DIR}/logs/metrics"

mkdir -p "$STATE_DIR" "$COOLDOWN_DIR" "$FLAP_DIR" "$METRICS_DIR" "$(dirname "$LOG_FILE")"

# ─── Constants ────────────────────────────────────────────────
FLAP_WINDOW=300        # 5 minutes
FLAP_THRESHOLD=3       # 3 transitions = flapping
OBSERVER_URL="https://axe.observer/api/messages"
OBSERVER_API_KEY="_J1ra0x7W-ray8Cat_NXyFIcHUgsSRK5PnN3g0b9WUU"
VERSION="2.0.0"

# ─── Logging ──────────────────────────────────────────────────
log() {
    local level="$1"; shift
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [$level] $*" >> "$LOG_FILE"
}

# ─── Structured Event Log (for AI/ML training) ───────────────
log_event() {
    local target="$1"
    local event_type="$2"
    local old_state="$3"
    local new_state="$4"
    local latency_ms="${5:-0}"
    local metadata="${6:-{}}"

    python3 -c "
import json, datetime
event = {
    'timestamp': datetime.datetime.utcnow().isoformat() + 'Z',
    'target': '$target',
    'event': '$event_type',
    'old_state': '$old_state',
    'new_state': '$new_state',
    'latency_ms': $latency_ms,
    'metadata': $metadata,
    'version': '$VERSION'
}
print(json.dumps(event))
" >> "$EVENTS_LOG" 2>/dev/null
}

log "INFO" "═══ AXE Fleet Notify v${VERSION} starting ═══"

# ─── Config parsing ───────────────────────────────────────────
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

log "INFO" "Poll: ${POLL_INTERVAL}s | Cooldown: ${COOLDOWN_SECONDS}s | Flap threshold: ${FLAP_THRESHOLD}/${FLAP_WINDOW}s"

# ─── axe.observer Reporting ──────────────────────────────────
report_to_observer() {
    local message="$1"
    local msg_type="${2:-fleet-notify}"

    # Fire and forget — don't block monitoring
    (curl -s -X POST "$OBSERVER_URL" \
        -H "Content-Type: application/json" \
        -H "X-API-Key: $OBSERVER_API_KEY" \
        -d "{\"from\":\"forge-fleet\",\"to\":\"team\",\"msg\":\"$message\",\"type\":\"$msg_type\"}" \
        --connect-timeout 5 --max-time 10 \
        &>/dev/null || true) &
}


# ─── ntfy Push (iPhone/Android/Desktop) ──────────────────────
push_ntfy() {
    local title="$1"
    local message="$2"
    local priority="${3:-3}"
    local tags="${4:-axe}"
    local event_type="${5:-info}"

    # Check if ntfy is enabled
    local ntfy_enabled
    ntfy_enabled=$(parse_json "print(cfg.get('ntfy', {}).get('enabled', False))")
    if [[ "$ntfy_enabled" != "True" ]]; then
        return 0
    fi

    local ntfy_server
    ntfy_server=$(parse_json "print(cfg.get('ntfy', {}).get('server', 'https://ntfy.sh'))")
    local ntfy_topic
    ntfy_topic=$(parse_json "print(cfg.get('ntfy', {}).get('topic', 'axe-fleet'))")

    # Check quiet hours
    local quiet_enabled
    quiet_enabled=$(parse_json "print(cfg.get('ntfy', {}).get('quiet_hours', {}).get('enabled', False))")
    if [[ "$quiet_enabled" == "True" ]]; then
        local current_hour=$(date +%H)
        local quiet_start
        quiet_start=$(parse_json "print(cfg.get('ntfy', {}).get('quiet_hours', {}).get('start', '23:00').split(':')[0])")
        local quiet_end
        quiet_end=$(parse_json "print(cfg.get('ntfy', {}).get('quiet_hours', {}).get('end', '07:00').split(':')[0])")
        if [[ "$current_hour" -ge "$quiet_start" || "$current_hour" -lt "$quiet_end" ]]; then
            # During quiet hours, only push priority 5 (critical)
            if [[ "$priority" -lt 5 ]]; then
                return 0
            fi
        fi
    fi

    # Fire and forget
    (curl -s -X POST "${ntfy_server}/${ntfy_topic}" \
        -H "Title: ${title}" \
        -H "Priority: ${priority}" \
        -H "Tags: ${tags}" \
        -d "${message}" \
        --connect-timeout 5 --max-time 10 \
        &>/dev/null || true) &

    log "NTFY" "[P${priority}] ${title} — ${message}"
}

# ─── Flap Detection ──────────────────────────────────────────
record_flap() {
    local key="$1"
    local flap_file="${FLAP_DIR}/${key}"
    local now=$(date +%s)

    # Append current timestamp
    echo "$now" >> "$flap_file"

    # Prune entries older than FLAP_WINDOW
    if [[ -f "$flap_file" ]]; then
        local cutoff=$((now - FLAP_WINDOW))
        local tmp=$(mktemp)
        awk -v cutoff="$cutoff" '$1 >= cutoff' "$flap_file" > "$tmp" && mv "$tmp" "$flap_file"
    fi
}

is_flapping() {
    local key="$1"
    local flap_file="${FLAP_DIR}/${key}"

    if [[ ! -f "$flap_file" ]]; then
        echo "false"
        return
    fi

    local count
    count=$(wc -l < "$flap_file" | tr -d ' ')

    if [[ "$count" -ge "$FLAP_THRESHOLD" ]]; then
        echo "true"
    else
        echo "false"
    fi
}

get_flap_count() {
    local key="$1"
    local flap_file="${FLAP_DIR}/${key}"
    if [[ -f "$flap_file" ]]; then
        wc -l < "$flap_file" | tr -d ' '
    else
        echo "0"
    fi
}

# ─── Notification Engine ──────────────────────────────────────
notify() {
    local title="$1"
    local message="$2"
    local sound="${3:-Glass}"
    local key="$4"
    local report="${5:-true}"

    # Cooldown check
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

    # Report to axe.observer data tower
    if [[ "$report" == "true" ]]; then
        local clean_msg=$(echo "$message" | sed 's/"/\\"/g')
        report_to_observer "🪓 ${title}: ${clean_msg}"
    fi

    log "NOTIFY" "[$sound] $title — $message"

    # Push to ntfy for iPhone/mobile notifications
    local ntfy_priority=3
    local ntfy_tags="axe"
    if [[ "$sound" == "Basso" ]]; then
        ntfy_priority=5; ntfy_tags="rotating_light,skull"
    elif [[ "$sound" == "Hero" ]]; then
        ntfy_priority=3; ntfy_tags="white_check_mark,rocket"
    elif [[ "$sound" == "Purr" ]]; then
        ntfy_priority=3; ntfy_tags="warning"
    elif [[ "$sound" == "Submarine" ]]; then
        ntfy_priority=4; ntfy_tags="cyclone"
    elif [[ "$sound" == "Pop" ]]; then
        ntfy_priority=2; ntfy_tags="thumbsup"
    fi
    push_ntfy "$title" "$message" "$ntfy_priority" "$ntfy_tags"
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

# ─── Check: Ping with latency ────────────────────────────────
check_ping() {
    local ip="$1"
    local result
    result=$(ping -c 1 -W 2 "$ip" 2>/dev/null) || { echo "offline|0"; return; }

    local latency
    latency=$(echo "$result" | grep "time=" | sed 's/.*time=\([0-9.]*\).*/\1/' | head -1)
    echo "online|${latency:-0}"
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

# ─── Check: HTTP endpoint with response time ─────────────────
check_http() {
    local url="$1"
    local result
    result=$(curl -s -o /dev/null -w "%{http_code}|%{time_total}" --connect-timeout 5 --max-time 10 "$url" 2>/dev/null || echo "000|0")
    local status=$(echo "$result" | cut -d'|' -f1)
    local time_s=$(echo "$result" | cut -d'|' -f2)
    local time_ms=$(python3 -c "print(int(float('${time_s}') * 1000))" 2>/dev/null || echo "0")

    if [[ "$status" -ge 200 && "$status" -lt 400 ]]; then
        echo "up|${time_ms}"
    else
        echo "down|${time_ms}"
    fi
}

# ─── Save Metric (for trend analysis) ────────────────────────
save_metric() {
    local key="$1"
    local value="$2"
    local metric_file="${METRICS_DIR}/${key}.csv"
    local now=$(date +%s)

    echo "${now},${value}" >> "$metric_file"

    # Keep only last 1000 data points per metric
    if [[ -f "$metric_file" ]]; then
        local lines
        lines=$(wc -l < "$metric_file" | tr -d ' ')
        if [[ "$lines" -gt 1000 ]]; then
            local tmp=$(mktemp)
            tail -1000 "$metric_file" > "$tmp" && mv "$tmp" "$metric_file"
        fi
    fi
}

# ─── Anomaly Detection (simple z-score on latency) ───────────
check_anomaly() {
    local key="$1"
    local current_ms="$2"
    local metric_file="${METRICS_DIR}/${key}.csv"

    if [[ ! -f "$metric_file" ]]; then
        return 0
    fi

    local count
    count=$(wc -l < "$metric_file" | tr -d ' ')

    # Need at least 20 data points for meaningful stats
    if [[ "$count" -lt 20 ]]; then
        return 0
    fi

    # Calculate mean and stddev, check if current is anomalous (>3 sigma)
    python3 -c "
import statistics
values = []
with open('$metric_file') as f:
    for line in f:
        parts = line.strip().split(',')
        if len(parts) == 2:
            try:
                values.append(float(parts[1]))
            except:
                pass

if len(values) < 20:
    exit(0)

mean = statistics.mean(values)
stdev = statistics.stdev(values)
current = float($current_ms)

if stdev > 0 and current > mean + (3 * stdev) and current > 100:
    zscore = (current - mean) / stdev
    print(f'ANOMALY: {current:.0f}ms is {zscore:.1f}σ above mean {mean:.0f}ms')
" 2>/dev/null | while read -r anomaly_msg; do
        if [[ -n "$anomaly_msg" ]]; then
            notify "📊 AXE Anomaly" "${key}: ${anomaly_msg}" "Purr" "anomaly_${key}" "true"
            log_event "$key" "anomaly" "normal" "anomalous" "$current_ms" "{\"message\":\"$anomaly_msg\"}"
        fi
    done
}

# ─── Handle state transition with flap detection ─────────────
handle_transition() {
    local key="$1"
    local name="$2"
    local new_state="$3"
    local tier="$4"
    local latency="${5:-0}"
    local category="${6:-fleet}"

    local prev
    prev=$(get_state "$key")

    if [[ "$new_state" == "$prev" ]]; then
        return 0
    fi

    set_state "$key" "$new_state"
    record_flap "$key"

    local flapping
    flapping=$(is_flapping "$key")
    local flap_count
    flap_count=$(get_flap_count "$key")

    if [[ "$flapping" == "true" ]]; then
        # Suppress individual alerts, send flapping warning instead
        notify "🔄 FLAPPING" "${name} — ${flap_count} state changes in 5min (suppressed)" "Submarine" "flap_${key}" "true"
        log_event "$key" "flapping" "$prev" "$new_state" "$latency" "{\"flap_count\":$flap_count,\"tier\":$tier}"
        return 0
    fi

    # Normal transition — fire appropriate notification
    log_event "$key" "transition" "$prev" "$new_state" "$latency" "{\"tier\":$tier,\"category\":\"$category\"}"

    if [[ "$new_state" == "online" || "$new_state" == "up" ]]; then
        local sound="Pop"
        [[ "$tier" -le 1 ]] && sound="Hero"
        local icon="✅"
        [[ "$category" == "web" ]] && icon="🌐"
        [[ "$category" == "droplet" ]] && icon="☁️"
        [[ "$category" == "wireguard" ]] && icon="🔒"
        notify "${icon} AXE ${category^}" "${name} is UP" "$sound" "${key}" "true"
    else
        local sound="Purr"
        [[ "$tier" -le 1 ]] && sound="Basso"
        local icon="🔴"
        [[ "$category" == "wireguard" ]] && icon="🔓"
        notify "${icon} AXE ${category^}" "${name} is DOWN" "$sound" "${key}" "true"
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

        if [[ "$do_ping" == "True" ]]; then
            local ping_result
            ping_result=$(check_ping "$ip")
            local status=$(echo "$ping_result" | cut -d'|' -f1)
            local latency=$(echo "$ping_result" | cut -d'|' -f2)

            # Save latency metric
            if [[ "$status" == "online" ]]; then
                save_metric "ping_${key}" "$latency"
                check_anomaly "ping_${key}" "$latency"
            fi

            handle_transition "fleet_${key}_ping" "$name" "$status" "$tier" "${latency%.*}" "fleet"

            # Only check services if host is online
            if [[ "$status" == "online" ]]; then
                echo "$services_json" | python3 -c "
import json, sys
services = json.load(sys.stdin)
for svc in services:
    n = svc['name']
    p = svc['port']
    pr = svc.get('protocol', 'tcp')
    pa = svc.get('path', '/')
    print(f'{n}|{p}|{pr}|{pa}')
" 2>/dev/null | while IFS='|' read -r svc_name svc_port svc_proto svc_path; do
                    local svc_status svc_latency=0
                    if [[ "$svc_proto" == "http" ]]; then
                        local http_result
                        http_result=$(check_http "http://${ip}:${svc_port}${svc_path}")
                        svc_status=$(echo "$http_result" | cut -d'|' -f1)
                        svc_latency=$(echo "$http_result" | cut -d'|' -f2)
                        save_metric "http_${key}_${svc_name// /_}" "$svc_latency"
                        check_anomaly "http_${key}_${svc_name// /_}" "$svc_latency"
                    else
                        svc_status=$(check_tcp "$ip" "$svc_port")
                    fi

                    local svc_key="fleet_${key}_svc_${svc_name// /_}"
                    handle_transition "$svc_key" "${name} → ${svc_name} (:${svc_port})" "$svc_status" "$tier" "$svc_latency" "service"
                done
            fi
        else
            # Local machine — just check services
            echo "$services_json" | python3 -c "
import json, sys
services = json.load(sys.stdin)
for svc in services:
    n = svc['name']
    p = svc['port']
    pr = svc.get('protocol', 'tcp')
    pa = svc.get('path', '/')
    print(f'{n}|{p}|{pr}|{pa}')
" 2>/dev/null | while IFS='|' read -r svc_name svc_port svc_proto svc_path; do
                local svc_status svc_latency=0
                if [[ "$svc_proto" == "http" ]]; then
                    local http_result
                    http_result=$(check_http "http://127.0.0.1:${svc_port}${svc_path}")
                    svc_status=$(echo "$http_result" | cut -d'|' -f1)
                    svc_latency=$(echo "$http_result" | cut -d'|' -f2)
                    save_metric "http_local_${svc_name// /_}" "$svc_latency"
                else
                    svc_status=$(check_tcp "127.0.0.1" "$svc_port")
                fi

                local svc_key="local_svc_${svc_name// /_}"
                handle_transition "$svc_key" "JL2 → ${svc_name} (:${svc_port})" "$svc_status" "1" "$svc_latency" "service"
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
        local http_result
        http_result=$(check_http "$url")
        local status=$(echo "$http_result" | cut -d'|' -f1)
        local latency=$(echo "$http_result" | cut -d'|' -f2)

        save_metric "web_${key}" "$latency"
        check_anomaly "web_${key}" "$latency"
        handle_transition "web_${key}" "$name" "$status" "$tier" "$latency" "web"
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
        local ping_result
        ping_result=$(check_ping "$ip")
        local status=$(echo "$ping_result" | cut -d'|' -f1)
        local latency=$(echo "$ping_result" | cut -d'|' -f2)

        if [[ "$status" == "online" ]]; then
            save_metric "wg_${key}" "$latency"
        fi

        local wg_state="up"
        [[ "$status" != "online" ]] && wg_state="down"
        handle_transition "wg_${key}" "WG mesh → ${key} (${ip})" "$wg_state" "1" "${latency%.*}" "wireguard"
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
        local ping_result
        ping_result=$(check_ping "$ip")
        local status=$(echo "$ping_result" | cut -d'|' -f1)
        local latency=$(echo "$ping_result" | cut -d'|' -f2)

        if [[ "$status" == "online" ]]; then
            save_metric "droplet_${key}" "$latency"
        fi

        handle_transition "droplet_${key}_ping" "$name" "$status" "$tier" "${latency%.*}" "droplet"

        if [[ "$status" == "online" ]]; then
            echo "$services_json" | python3 -c "
import json, sys
services = json.load(sys.stdin)
for svc in services:
    n = svc['name']
    p = svc['port']
    pr = svc.get('protocol', 'tcp')
    pa = svc.get('path', '/')
    print(f'{n}|{p}|{pr}|{pa}')
" 2>/dev/null | while IFS='|' read -r svc_name svc_port svc_proto svc_path; do
                local svc_status svc_latency=0
                if [[ "$svc_proto" == "http" ]]; then
                    local http_result
                    http_result=$(check_http "http://${ip}:${svc_port}${svc_path}")
                    svc_status=$(echo "$http_result" | cut -d'|' -f1)
                    svc_latency=$(echo "$http_result" | cut -d'|' -f2)
                elif [[ "$svc_port" == "443" ]]; then
                    svc_status=$(check_tcp "$ip" "$svc_port")
                else
                    svc_status=$(check_tcp "$ip" "$svc_port")
                fi

                handle_transition "droplet_${key}_svc_${svc_name// /_}" "${name} → ${svc_name}" "$svc_status" "$tier" "$svc_latency" "droplet"
            done
        fi
    done
}

# ─── Daily Summary (fires at first check after midnight) ─────
check_daily_summary() {
    local today=$(date +%Y-%m-%d)
    local summary_file="${STATE_DIR}/_last_summary"

    if [[ -f "$summary_file" ]] && [[ "$(cat "$summary_file")" == "$today" ]]; then
        return 0
    fi

    echo "$today" > "$summary_file"

    # Count current states
    local online=0 offline=0 services_up=0 services_down=0 web_up=0 web_down=0

    for f in "${STATE_DIR}"/fleet_*_ping; do
        [[ -f "$f" ]] || continue
        [[ "$(cat "$f")" == "online" ]] && ((online++)) || ((offline++))
    done

    for f in "${STATE_DIR}"/fleet_*_svc_* "${STATE_DIR}"/local_svc_*; do
        [[ -f "$f" ]] || continue
        [[ "$(cat "$f")" == "up" ]] && ((services_up++)) || ((services_down++))
    done

    for f in "${STATE_DIR}"/web_*; do
        [[ -f "$f" ]] || continue
        [[ "$(cat "$f")" == "up" ]] && ((web_up++)) || ((web_down++))
    done

    local summary="Daily: ${online} machines online, ${offline} offline | ${services_up} services up, ${services_down} down | ${web_up} web up, ${web_down} down"

    notify "📊 AXE Daily Summary" "$summary" "Glass" "daily_summary" "true"
    log_event "system" "daily_summary" "none" "none" "0" "{\"machines_online\":$online,\"machines_offline\":$offline,\"services_up\":$services_up,\"services_down\":$services_down,\"web_up\":$web_up,\"web_down\":$web_down}"
}

# ─── Status CLI ───────────────────────────────────────────────
if [[ "${1:-}" == "status" ]]; then
    echo "═══ AXE Fleet Status (v${VERSION}) ═══"
    echo ""
    echo "Fleet Machines:"
    for f in "${STATE_DIR}"/fleet_*_ping; do
        [[ -f "$f" ]] || continue
        key=$(basename "$f" | sed 's/fleet_//;s/_ping//')
        status=$(cat "$f")
        flap_count=$(get_flap_count "fleet_${key}_ping")
        icon="🔴"
        [[ "$status" == "online" ]] && icon="✅"
        extra=""
        [[ "$flap_count" -ge "$FLAP_THRESHOLD" ]] && extra=" ⚠️ FLAPPING (${flap_count}x)"
        echo "  $icon $key: $status${extra}"

        # Show services for this machine
        for sf in "${STATE_DIR}"/fleet_${key}_svc_*; do
            [[ -f "$sf" ]] || continue
            svc_name=$(basename "$sf" | sed "s/fleet_${key}_svc_//")
            svc_status=$(cat "$sf")
            svc_icon="  🔴"
            [[ "$svc_status" == "up" ]] && svc_icon="  ✅"
            echo "    $svc_icon $svc_name: $svc_status"
        done
    done

    echo ""
    echo "Local Services (JL2):"
    for f in "${STATE_DIR}"/local_svc_*; do
        [[ -f "$f" ]] || continue
        key=$(basename "$f" | sed 's/local_svc_//')
        status=$(cat "$f")
        icon="🔴"
        [[ "$status" == "up" ]] && icon="✅"
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
    echo "Events (last 24h):"
    if [[ -f "$EVENTS_LOG" ]]; then
        today=$(date +%Y-%m-%d)
        grep "$today" "$EVENTS_LOG" 2>/dev/null | wc -l | xargs -I{} echo "  {} events today"
        echo "  Last 5:"
        tail -5 "$EVENTS_LOG" | python3 -c "
import json, sys
for line in sys.stdin:
    try:
        e = json.loads(line.strip())
        print(f\"    {e['timestamp'][:19]} {e['target']}: {e['old_state']}→{e['new_state']} ({e['event']})\")
    except:
        pass
" 2>/dev/null
    else
        echo "  (no events yet)"
    fi

    echo ""
    echo "Metrics files: $(ls "${METRICS_DIR}"/*.csv 2>/dev/null | wc -l | tr -d ' ') tracked"
    echo "Log: $LOG_FILE"
    exit 0
fi

# ─── Main Loop ────────────────────────────────────────────────
log "INFO" "Starting monitoring loop (${POLL_INTERVAL}s interval)"
report_to_observer "🪓 AXE Fleet Notify v${VERSION} started — monitoring all services"
notify "🪓 AXE Fleet" "Fleet Notify v${VERSION} started — monitoring all services" "Glass" "daemon_start" "false"

trap 'log "INFO" "═══ AXE Fleet Notify stopping ═══"; report_to_observer "🪓 AXE Fleet Notify stopped"; notify "🪓 AXE Fleet" "Fleet Notify daemon stopped" "Basso" "daemon_stop" "false"; exit 0' SIGTERM SIGINT

while true; do
    check_daily_summary
    monitor_fleet
    monitor_web
    monitor_wireguard
    monitor_droplets
    sleep "$POLL_INTERVAL"
done
