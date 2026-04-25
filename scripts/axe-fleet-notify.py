#!/usr/bin/env python3
"""
AXE Fleet Notification Daemon v3.0
Enterprise-grade sovereign fleet monitoring.

Zero external dependencies. Zero API spend. Pure local iron.

Features:
  - Async concurrent health checks
  - Plugin notification channels (macOS, ntfy, observer, webhook)
  - Built-in health endpoint (:9999/health)
  - Flap detection & anomaly detection
  - Structured JSONL event log for AI/ML
  - PID lock (no duplicate daemons)
  - Log rotation
  - Config validation
  - Self-update check
"""

import asyncio
import csv
import datetime
import hashlib
import http.server
import io
import json
import logging
import os
import pathlib
import shutil
import signal
import socket
import statistics
import subprocess
import sys
import threading
import time
import urllib.error
import urllib.request
from collections import defaultdict
from dataclasses import dataclass, field, asdict
from enum import Enum
from typing import Any, Dict, List, Optional, Tuple

# Local model integration (Carmack Pattern — zero API spend)
try:
    sys.path.insert(0, os.path.expanduser("~/Desktop/axiom/axe-runway"))
    from axe_sdk import route, ensure_server, generate
    HAS_LOCAL_MODEL = True
except ImportError:
    HAS_LOCAL_MODEL = False

# Module-level AI summary engine (initialized in main())
smart_summary = None

# ─── Constants ────────────────────────────────────────────────
VERSION = "3.0.0"
APP_DIR = pathlib.Path(__file__).resolve().parent.parent
CONFIG_FILE = APP_DIR / "config" / "fleet-config.json"
LOG_DIR = APP_DIR / "logs"
STATE_DIR = LOG_DIR / "state"
COOLDOWN_DIR = LOG_DIR / "cooldown"
FLAP_DIR = LOG_DIR / "flap"
METRICS_DIR = LOG_DIR / "metrics"
EVENTS_LOG = LOG_DIR / "events.jsonl"
PID_FILE = LOG_DIR / "daemon.pid"
HEALTH_PORT = 9999

# ─── Setup Directories ───────────────────────────────────────
for d in [LOG_DIR, STATE_DIR, COOLDOWN_DIR, FLAP_DIR, METRICS_DIR]:
    d.mkdir(parents=True, exist_ok=True)

# ─── Logging with Rotation ───────────────────────────────────
class RotatingLog:
    """Simple log rotation without external deps."""
    
    def __init__(self, path: pathlib.Path, max_bytes: int = 10_000_000, backup_count: int = 5):
        self.path = path
        self.max_bytes = max_bytes
        self.backup_count = backup_count
    
    def write(self, message: str):
        if self.path.exists() and self.path.stat().st_size > self.max_bytes:
            self._rotate()
        with open(self.path, "a") as f:
            f.write(message + "\n")
    
    def _rotate(self):
        for i in range(self.backup_count - 1, 0, -1):
            src = self.path.with_suffix(f".log.{i}")
            dst = self.path.with_suffix(f".log.{i + 1}")
            if src.exists():
                shutil.move(str(src), str(dst))
        if self.path.exists():
            shutil.move(str(self.path), str(self.path.with_suffix(".log.1")))

logger = RotatingLog(LOG_DIR / "axe-fleet-notify.log")

def log(level: str, msg: str):
    ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
    logger.write(f"[{ts}] [{level}] {msg}")


# ─── Data Classes ─────────────────────────────────────────────
class Tier(Enum):
    CRITICAL = 1
    IMPORTANT = 2
    PERIPHERAL = 3

@dataclass
class CheckResult:
    target: str
    name: str
    status: str  # "online"/"offline" or "up"/"down"
    latency_ms: float = 0.0
    tier: int = 2
    category: str = "fleet"
    metadata: Dict[str, Any] = field(default_factory=dict)

@dataclass
class FleetState:
    """Global daemon state — thread-safe reads via GIL."""
    checks_total: int = 0
    checks_failed: int = 0
    last_check_time: str = ""
    uptime_start: str = ""
    notifications_sent: int = 0
    events_logged: int = 0
    version: str = VERSION
    fleet_online: int = 0
    fleet_offline: int = 0
    services_up: int = 0
    services_down: int = 0
    web_up: int = 0
    web_down: int = 0

state = FleetState(uptime_start=datetime.datetime.now(datetime.timezone.utc).isoformat() + "Z")


# ─── Config Loading & Validation ──────────────────────────────
def load_config() -> dict:
    if not CONFIG_FILE.exists():
        log("FATAL", f"Config not found: {CONFIG_FILE}")
        sys.exit(1)
    
    with open(CONFIG_FILE) as f:
        cfg = json.load(f)
    
    errors = []
    
    # Required top-level keys
    for key in ["poll_interval_seconds", "fleet", "web_services"]:
        if key not in cfg:
            errors.append(f"Missing required key: {key}")
    
    # Validate fleet machines
    for name, machine in cfg.get("fleet", {}).items():
        for req in ["name", "ip", "tier"]:
            if req not in machine:
                errors.append(f"fleet.{name} missing '{req}'")
        for svc in machine.get("services", []):
            if "name" not in svc or "port" not in svc:
                errors.append(f"fleet.{name} service missing name/port")
    
    # Validate web services
    for name, svc in cfg.get("web_services", {}).items():
        if "url" not in svc:
            errors.append(f"web_services.{name} missing 'url'")
    
    if errors:
        log("ERROR", f"Config validation failed: {'; '.join(errors)}")
        print(f"[ERROR] Config validation failed:\n" + "\n".join(f"  - {e}" for e in errors))
        sys.exit(1)
    
    log("INFO", f"Config loaded: {len(cfg.get('fleet', {}))} machines, "
                 f"{len(cfg.get('web_services', {}))} web services, "
                 f"{len(cfg.get('droplets', {}))} droplets")
    return cfg


# ─── PID Lock ─────────────────────────────────────────────────
def acquire_pid_lock():
    if PID_FILE.exists():
        old_pid = PID_FILE.read_text().strip()
        try:
            os.kill(int(old_pid), 0)
            log("FATAL", f"Another instance running (PID {old_pid})")
            print(f"[ERROR] Another daemon is already running (PID {old_pid})")
            print(f"   Kill it with: kill {old_pid}")
            sys.exit(1)
        except (ProcessLookupError, ValueError):
            log("WARN", f"Stale PID file found (PID {old_pid}), removing")
    
    PID_FILE.write_text(str(os.getpid()))
    log("INFO", f"PID lock acquired: {os.getpid()}")

def release_pid_lock():
    if PID_FILE.exists():
        PID_FILE.unlink()


# ─── Notification Plugins ────────────────────────────────────
class NotificationChannel:
    """Base class for notification channels."""
    name: str = "base"
    
    def send(self, title: str, message: str, priority: int = 3, tags: str = "", **kwargs):
        raise NotImplementedError


class MacOSNotification(NotificationChannel):
    name = "macos"
    
    SOUND_MAP = {
        5: "Basso",      # Critical down
        4: "Submarine",  # Flapping/anomaly
        3: "Hero",       # Recovery
        2: "Pop",        # Info up
        1: "Glass",      # Daily/low priority
    }
    
    def send(self, title: str, message: str, priority: int = 3, sound: str = "", **kwargs):
        snd = sound or self.SOUND_MAP.get(priority, "Glass")
        try:
            subprocess.run(
                ["osascript", "-e", f'display notification "{message}" with title "{title}" sound name "{snd}"'],
                capture_output=True, timeout=5
            )
        except Exception as e:
            log("ERROR", f"macOS notification failed: {e}")


class NtfyNotification(NotificationChannel):
    name = "ntfy"
    
    def __init__(self, config: dict):
        self.enabled = config.get("enabled", False)
        self.server = config.get("server", "https://ntfy.sh")
        self.topic = config.get("topic", "axe-fleet")
        self.quiet_hours = config.get("quiet_hours", {})
    
    def _in_quiet_hours(self) -> bool:
        if not self.quiet_hours.get("enabled", False):
            return False
        now = datetime.datetime.now().hour
        start = int(self.quiet_hours.get("start", "23:00").split(":")[0])
        end = int(self.quiet_hours.get("end", "07:00").split(":")[0])
        if start > end:
            return now >= start or now < end
        return start <= now < end
    
    def send(self, title: str, message: str, priority: int = 3, tags: str = "axe", **kwargs):
        if not self.enabled:
            return
        if self._in_quiet_hours() and priority < 5:
            return
        
        url = f"{self.server}/{self.topic}"
        data = message.encode("utf-8")
        req = urllib.request.Request(url, data=data, method="POST")
        req.add_header("Title", title)
        req.add_header("Priority", str(priority))
        req.add_header("Tags", tags)
        
        try:
            urllib.request.urlopen(req, timeout=10)
            log("NTFY", f"[P{priority}] {title}")
        except Exception as e:
            log("ERROR", f"ntfy push failed: {e}")


class ObserverNotification(NotificationChannel):
    name = "observer"
    
    def __init__(self, url: str = "https://axe.observer/api/messages", 
                 api_key: str = "_J1ra0x7W-ray8Cat_NXyFIcHUgsSRK5PnN3g0b9WUU"):
        self.url = url
        self.api_key = api_key
    
    def send(self, title: str, message: str, **kwargs):
        payload = json.dumps({
            "from": "forge-fleet",
            "to": "team",
            "msg": f"[AXE] {title}: {message}",
            "type": "fleet-notify"
        }).encode("utf-8")
        
        req = urllib.request.Request(self.url, data=payload, method="POST")
        req.add_header("Content-Type", "application/json")
        req.add_header("X-API-Key", self.api_key)
        
        try:
            urllib.request.urlopen(req, timeout=10)
        except Exception as e:
            log("ERROR", f"Observer report failed: {e}")


class WebhookNotification(NotificationChannel):
    """Generic webhook channel for future integrations."""
    name = "webhook"
    
    def __init__(self, config: dict):
        self.enabled = config.get("enabled", False)
        self.url = config.get("url", "")
        self.headers = config.get("headers", {})
    
    def send(self, title: str, message: str, priority: int = 3, **kwargs):
        if not self.enabled or not self.url:
            return
        
        payload = json.dumps({
            "title": title,
            "message": message,
            "priority": priority,
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat() + "Z",
            "source": "axe-fleet-notify",
            "version": VERSION
        }).encode("utf-8")
        
        req = urllib.request.Request(self.url, data=payload, method="POST")
        req.add_header("Content-Type", "application/json")
        for k, v in self.headers.items():
            req.add_header(k, v)
        
        try:
            urllib.request.urlopen(req, timeout=10)
        except Exception as e:
            log("ERROR", f"Webhook failed: {e}")


# ─── Notification Manager ────────────────────────────────────
class NotificationManager:
    def __init__(self, config: dict):
        self.channels: List[NotificationChannel] = []
        self.cooldowns: Dict[str, float] = {}
        self.cooldown_seconds = config.get("notification_cooldown_seconds", 300)
        
        # Always add macOS
        self.channels.append(MacOSNotification())
        
        # Add ntfy if configured
        ntfy_cfg = config.get("ntfy", {})
        if ntfy_cfg.get("enabled"):
            self.channels.append(NtfyNotification(ntfy_cfg))
        
        # Always add observer
        self.channels.append(ObserverNotification())
        
        # Add webhook if configured
        webhook_cfg = config.get("webhook", {})
        if webhook_cfg.get("enabled"):
            self.channels.append(WebhookNotification(webhook_cfg))
        
        log("INFO", f"Notification channels: {[c.name for c in self.channels]}")
    
    def notify(self, title: str, message: str, key: str, priority: int = 3, 
               sound: str = "", tags: str = "axe", skip_observer: bool = False):
        # Cooldown check
        now = time.time()
        if key in self.cooldowns:
            elapsed = now - self.cooldowns[key]
            if elapsed < self.cooldown_seconds:
                return
        
        self.cooldowns[key] = now
        state.notifications_sent += 1
        
        # Fan out to all channels
        for channel in self.channels:
            if skip_observer and channel.name == "observer":
                continue
            try:
                threading.Thread(
                    target=channel.send,
                    args=(title, message),
                    kwargs={"priority": priority, "sound": sound, "tags": tags},
                    daemon=True
                ).start()
            except Exception as e:
                log("ERROR", f"Channel {channel.name} dispatch failed: {e}")
        
        log("NOTIFY", f"[P{priority}] {title} — {message}")


# ─── Flap Detection ──────────────────────────────────────────
class FlapDetector:
    def __init__(self, window: int = 300, threshold: int = 3):
        self.window = window
        self.threshold = threshold
        self.transitions: Dict[str, List[float]] = defaultdict(list)
    
    def record(self, key: str) -> Tuple[bool, int]:
        now = time.time()
        self.transitions[key].append(now)
        
        # Prune old entries
        cutoff = now - self.window
        self.transitions[key] = [t for t in self.transitions[key] if t >= cutoff]
        
        count = len(self.transitions[key])
        is_flapping = count >= self.threshold
        
        # Persist for status CLI
        flap_file = FLAP_DIR / key
        flap_file.write_text("\n".join(str(t) for t in self.transitions[key]))
        
        return is_flapping, count


# ─── Anomaly Detection ───────────────────────────────────────
class AnomalyDetector:
    def __init__(self, min_samples: int = 20, sigma_threshold: float = 3.0):
        self.min_samples = min_samples
        self.sigma = sigma_threshold
    
    def check(self, key: str, value: float) -> Optional[str]:
        metric_file = METRICS_DIR / f"{key}.csv"
        
        if not metric_file.exists():
            return None
        
        values = []
        with open(metric_file) as f:
            reader = csv.reader(f)
            for row in reader:
                if len(row) == 2:
                    try:
                        values.append(float(row[1]))
                    except ValueError:
                        pass
        
        if len(values) < self.min_samples:
            return None
        
        mean = statistics.mean(values)
        stdev = statistics.stdev(values)
        
        if stdev > 0 and value > mean + (self.sigma * stdev) and value > 100:
            zscore = (value - mean) / stdev
            return f"{value:.0f}ms is {zscore:.1f}σ above mean {mean:.0f}ms"
        
        return None


# ─── Smart Summary (Local Model Integration) ────────────────
class SmartSummary:
    """Fleet state summaries via local LLM. Carmack Pattern: route -> ensure_server -> generate."""

    def __init__(self):
        self._last_summary: str = ""
        self._last_generated: float = 0
        self._cooldown: float = 120
        self._incident_log: list = []
        self._max_incidents: int = 10
        self._lock = threading.Lock()

    def generate_fleet_summary(self, status_data: dict) -> str:
        now = time.time()
        if now - self._last_generated < self._cooldown and self._last_summary:
            return self._last_summary

        if not HAS_LOCAL_MODEL:
            return self._fallback_summary(status_data)

        try:
            r = route("general")
            r = ensure_server(r)
            prompt = self._build_prompt(status_data)
            result = generate(r, prompt, max_tokens=150)
            if result and isinstance(result, str) and len(result.strip()) > 10:
                with self._lock:
                    self._last_summary = result.strip()
                    self._last_generated = now
                return self._last_summary
        except Exception as e:
            log("WARN", f"Local model summary failed: {e}")

        return self._fallback_summary(status_data)

    def generate_incident_summary(self, key: str, name: str,
                                   prev_state: str, new_state: str,
                                   category: str):
        if not HAS_LOCAL_MODEL:
            return

        try:
            r = route("general")
            r = ensure_server(r)
            prompt = (
                f"AXE Fleet incident. One sentence analysis, no emojis.\n"
                f"Target: {name} ({category})\n"
                f"Change: {prev_state} -> {new_state}\n"
                f"Analysis:"
            )
            result = generate(r, prompt, max_tokens=80)
            if result and isinstance(result, str) and len(result.strip()) > 5:
                with self._lock:
                    self._incident_log.insert(0, {
                        "target": name,
                        "change": f"{prev_state} -> {new_state}",
                        "analysis": result.strip(),
                        "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat() + "Z"
                    })
                    if len(self._incident_log) > self._max_incidents:
                        self._incident_log = self._incident_log[:self._max_incidents]
        except Exception as e:
            log("WARN", f"Local model incident analysis failed: {e}")

    def get_latest(self) -> dict:
        with self._lock:
            return {
                "fleet_summary": self._last_summary or "Awaiting first summary cycle",
                "last_generated": self._last_generated,
                "incidents": list(self._incident_log[:5]),
                "model_available": HAS_LOCAL_MODEL,
                "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat() + "Z"
            }

    def _build_prompt(self, status_data: dict) -> str:
        fleet = status_data.get("fleet", {})
        web = status_data.get("web", {})
        wg = status_data.get("wireguard", {})
        online = sum(1 for v in fleet.values() if v in ("online", "up"))
        offline = sum(1 for v in fleet.values() if v in ("offline", "down"))
        web_up = sum(1 for v in web.values() if v in ("online", "up"))
        web_down = sum(1 for v in web.values() if v in ("offline", "down"))
        return (
            f"AXE Fleet status. Two sentences max, no emojis.\n"
            f"Fleet: {online} online, {offline} offline.\n"
            f"Web: {web_up} up, {web_down} down.\n"
            f"WireGuard: {len(wg)} peers.\n"
            f"Summary:"
        )

    def _fallback_summary(self, status_data: dict) -> str:
        fleet = status_data.get("fleet", {})
        web = status_data.get("web", {})
        online = sum(1 for v in fleet.values() if v in ("online", "up"))
        total_f = len(fleet)
        web_up = sum(1 for v in web.values() if v in ("online", "up"))
        total_w = len(web)
        if online == total_f and web_up == total_w:
            return f"All systems nominal. {online}/{total_f} machines, {web_up}/{total_w} services operational."
        return f"Degraded state. {online}/{total_f} machines online, {web_up}/{total_w} services up."


# ─── Metrics Storage ──────────────────────────────────────────
class MetricsStore:
    MAX_POINTS = 1000
    
    def save(self, key: str, value: float):
        metric_file = METRICS_DIR / f"{key}.csv"
        now = int(time.time())
        
        with open(metric_file, "a") as f:
            f.write(f"{now},{value}\n")
        
        # Trim to max points
        if metric_file.exists():
            lines = metric_file.read_text().strip().split("\n")
            if len(lines) > self.MAX_POINTS:
                metric_file.write_text("\n".join(lines[-self.MAX_POINTS:]) + "\n")


# ─── Event Logger ─────────────────────────────────────────────
class EventLogger:
    def log_event(self, target: str, event_type: str, old_state: str, 
                  new_state: str, latency_ms: float = 0, metadata: dict = None):
        event = {
            "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat() + "Z",
            "target": target,
            "event": event_type,
            "old_state": old_state,
            "new_state": new_state,
            "latency_ms": round(latency_ms, 2),
            "metadata": metadata or {},
            "version": VERSION
        }
        
        with open(EVENTS_LOG, "a") as f:
            f.write(json.dumps(event) + "\n")
        
        state.events_logged += 1


# ─── Health Check Functions ───────────────────────────────────
async def check_ping(ip: str, timeout: float = 2.0) -> Tuple[str, float]:
    try:
        proc = await asyncio.create_subprocess_exec(
            "ping", "-c", "1", "-W", str(int(timeout)), ip,
            stdout=asyncio.subprocess.PIPE,
            stderr=asyncio.subprocess.PIPE
        )
        stdout, _ = await asyncio.wait_for(proc.communicate(), timeout=timeout + 1)
        
        if proc.returncode == 0:
            output = stdout.decode()
            # Extract latency
            for part in output.split("time="):
                if len(part) > 1:
                    try:
                        latency = float(part.split()[0].rstrip("ms"))
                        return "online", latency
                    except (ValueError, IndexError):
                        pass
            return "online", 0.0
        return "offline", 0.0
    except (asyncio.TimeoutError, Exception):
        return "offline", 0.0


async def check_tcp(ip: str, port: int, timeout: float = 3.0) -> str:
    try:
        _, writer = await asyncio.wait_for(
            asyncio.open_connection(ip, port),
            timeout=timeout
        )
        writer.close()
        await writer.wait_closed()
        return "up"
    except (asyncio.TimeoutError, ConnectionRefusedError, OSError):
        return "down"


async def check_http(url: str, timeout: float = 10.0, retries: int = 2) -> Tuple[str, float]:
    for attempt in range(retries):
        start = time.monotonic()
        try:
            req = urllib.request.Request(url, method="GET")
            req.add_header("User-Agent", f"AXE-Fleet-Notify/{VERSION}")
            
            loop = asyncio.get_event_loop()
            response = await loop.run_in_executor(
                None, lambda: urllib.request.urlopen(req, timeout=timeout)
            )
            
            elapsed_ms = (time.monotonic() - start) * 1000
            status_code = response.getcode()
            
            if 200 <= status_code < 400:
                return "up", elapsed_ms
            return "down", elapsed_ms
            
        except Exception:
            elapsed_ms = (time.monotonic() - start) * 1000
            if attempt < retries - 1:
                await asyncio.sleep(1 * (attempt + 1))  # Exponential backoff
            else:
                return "down", elapsed_ms
    
    return "down", 0.0


# ─── State Management ────────────────────────────────────────
class StateManager:
    def get(self, key: str) -> str:
        state_file = STATE_DIR / key
        if state_file.exists():
            return state_file.read_text().strip()
        return "unknown"
    
    def set(self, key: str, value: str):
        state_file = STATE_DIR / key
        state_file.write_text(value)


# ─── Health HTTP Server ──────────────────────────────────────
class HealthHandler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path == "/health":
            body = json.dumps({
                "status": "healthy",
                "version": VERSION,
                "uptime_start": state.uptime_start,
                "checks_total": state.checks_total,
                "checks_failed": state.checks_failed,
                "notifications_sent": state.notifications_sent,
                "events_logged": state.events_logged,
                "fleet": {
                    "online": state.fleet_online,
                    "offline": state.fleet_offline,
                },
                "services": {
                    "up": state.services_up,
                    "down": state.services_down,
                },
                "web": {
                    "up": state.web_up,
                    "down": state.web_down,
                },
                "timestamp": datetime.datetime.now(datetime.timezone.utc).isoformat() + "Z"
            }).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body)
        
        elif self.path == "/status":
            # Render full status
            body = json.dumps(self._full_status()).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body)
        
        elif self.path == "/metrics":
            # Prometheus-style metrics
            lines = [
                f"# AXE Fleet Notify v{VERSION}",
                f"axe_fleet_checks_total {state.checks_total}",
                f"axe_fleet_checks_failed {state.checks_failed}",
                f"axe_fleet_notifications_sent {state.notifications_sent}",
                f"axe_fleet_events_logged {state.events_logged}",
                f"axe_fleet_machines_online {state.fleet_online}",
                f"axe_fleet_machines_offline {state.fleet_offline}",
                f"axe_fleet_services_up {state.services_up}",
                f"axe_fleet_services_down {state.services_down}",
                f"axe_fleet_web_up {state.web_up}",
                f"axe_fleet_web_down {state.web_down}",
            ]
            body = "\n".join(lines).encode()
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(body)
        
        elif self.path == "/summary":
            body = json.dumps(
                smart_summary.get_latest() if smart_summary else {"error": "not initialized"}
            ).encode()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(body)

        else:
            self.send_response(404)
            self.end_headers()
    
    def _full_status(self) -> dict:
        result = {"fleet": {}, "web": {}, "wireguard": {}, "droplets": {}}
        
        for f in STATE_DIR.iterdir():
            name = f.name
            value = f.read_text().strip()
            
            if name.startswith("fleet_"):
                result["fleet"][name] = value
            elif name.startswith("web_"):
                result["web"][name] = value
            elif name.startswith("wg_"):
                result["wireguard"][name] = value
            elif name.startswith("droplet_"):
                result["droplets"][name] = value
        
        return result
    
    def log_message(self, format, *args):
        pass  # Suppress HTTP server logging


def start_health_server():
    try:
        server = http.server.HTTPServer(("0.0.0.0", HEALTH_PORT), HealthHandler)
        server.daemon_threads = True
        thread = threading.Thread(target=server.serve_forever, daemon=True)
        thread.start()
        log("INFO", f"Health server started on :{HEALTH_PORT}")
    except OSError as e:
        log("WARN", f"Health server failed to start on :{HEALTH_PORT}: {e}")


# ─── Core Monitor ─────────────────────────────────────────────
class FleetMonitor:
    def __init__(self, config: dict):
        self.config = config
        self.poll_interval = config.get("poll_interval_seconds", 30)
        self.state_mgr = StateManager()
        self.notifier = NotificationManager(config)
        self.flap_detector = FlapDetector()
        self.anomaly_detector = AnomalyDetector()
        self.metrics = MetricsStore()
        self.events = EventLogger()
        self.running = True
    
    def handle_transition(self, key: str, name: str, new_state: str, 
                          tier: int, latency: float = 0, category: str = "fleet"):
        prev = self.state_mgr.get(key)
        
        if new_state == prev:
            return
        
        self.state_mgr.set(key, new_state)
        
        # Flap detection
        is_flapping, flap_count = self.flap_detector.record(key)
        
        if is_flapping:
            self.notifier.notify(
                "[~] FLAPPING",
                f"{name} — {flap_count} state changes in 5min (suppressed)",
                f"flap_{key}", priority=4, tags="flapping"
            )
            self.events.log_event(key, "flapping", prev, new_state, latency,
                                  {"flap_count": flap_count, "tier": tier})
            return
        
        # Log event
        self.events.log_event(key, "transition", prev, new_state, latency,
                              {"tier": tier, "category": category})
        
        # AI incident analysis (background, non-blocking)
        if smart_summary:
            threading.Thread(
                target=smart_summary.generate_incident_summary,
                args=(key, name, prev, new_state, category),
                daemon=True
            ).start()

        # Determine notification parameters
        is_up = new_state in ("online", "up")
        
        if is_up:
            priority = 3 if tier <= 1 else 2
            sound = "Hero" if tier <= 1 else "Pop"
            tags = "ok,recovery" if tier <= 1 else "ok"
            icon = {"fleet": "[+]", "web": "[WEB]", "droplet": "[CLOUD]", "wireguard": "[WG+]", "service": "[+]"}.get(category, "[+]")
        else:
            priority = 5 if tier <= 1 else 3
            sound = "Basso" if tier <= 1 else "Purr"
            tags = "critical,down" if tier <= 1 else "alert"
            icon = {"wireguard": "[WG-]"}.get(category, "[-]")
        
        state_word = "UP" if is_up else "DOWN"
        self.notifier.notify(
            f"{icon} AXE {category.title()}",
            f"{name} is {state_word}",
            key, priority=priority, sound=sound, tags=tags
        )
    
    async def monitor_fleet(self):
        fleet = self.config.get("fleet", {})
        tasks = []
        
        for key, machine in fleet.items():
            tasks.append(self._check_machine(key, machine))
        
        await asyncio.gather(*tasks, return_exceptions=True)
    
    async def _check_machine(self, key: str, machine: dict):
        name = machine["name"]
        ip = machine["ip"]
        tier = machine.get("tier", 3)
        do_ping = machine.get("ping", True)
        services = machine.get("services", [])
        
        if do_ping:
            status, latency = await check_ping(ip)
            state.checks_total += 1
            if status == "offline":
                state.checks_failed += 1
            
            if status == "online":
                self.metrics.save(f"ping_{key}", latency)
                anomaly = self.anomaly_detector.check(f"ping_{key}", latency)
                if anomaly:
                    self.notifier.notify("[!] Anomaly", f"{name} ping: {anomaly}",
                                        f"anomaly_ping_{key}", priority=4, tags="chart_with_upwards_trend")
            
            self.handle_transition(f"fleet_{key}_ping", name, status, tier, latency, "fleet")
            
            # Only check services if online
            if status != "online":
                return
        
        # Check services concurrently
        svc_tasks = []
        for svc in services:
            svc_tasks.append(self._check_service(key, name, ip if do_ping else "127.0.0.1", tier, svc))
        
        if svc_tasks:
            await asyncio.gather(*svc_tasks, return_exceptions=True)
    
    async def _check_service(self, machine_key: str, machine_name: str, ip: str, tier: int, svc: dict):
        svc_name = svc["name"]
        port = svc["port"]
        proto = svc.get("protocol", "tcp")
        path = svc.get("path", "/")
        
        state.checks_total += 1
        svc_status = "down"
        latency = 0.0
        
        if proto == "http":
            svc_status, latency = await check_http(f"http://{ip}:{port}{path}")
            metric_key = f"http_{machine_key}_{svc_name.replace(' ', '_')}"
            self.metrics.save(metric_key, latency)
            anomaly = self.anomaly_detector.check(metric_key, latency)
            if anomaly:
                self.notifier.notify("[!] Anomaly", f"{machine_name} {svc_name}: {anomaly}",
                                    f"anomaly_{metric_key}", priority=4, tags="chart_with_upwards_trend")
        else:
            svc_status = await check_tcp(ip, port)
        
        if svc_status == "down":
            state.checks_failed += 1
        
        svc_key = f"fleet_{machine_key}_svc_{svc_name.replace(' ', '_')}"
        self.handle_transition(svc_key, f"{machine_name} → {svc_name} (:{port})", svc_status, tier, latency, "service")
    
    async def monitor_web(self):
        web_services = self.config.get("web_services", {})
        tasks = []
        
        for key, svc in web_services.items():
            tasks.append(self._check_web(key, svc))
        
        await asyncio.gather(*tasks, return_exceptions=True)
    
    async def _check_web(self, key: str, svc: dict):
        name = svc["name"]
        url = svc["url"]
        tier = svc.get("tier", 2)
        
        state.checks_total += 1
        status, latency = await check_http(url)
        
        if status == "down":
            state.checks_failed += 1
        
        self.metrics.save(f"web_{key}", latency)
        anomaly = self.anomaly_detector.check(f"web_{key}", latency)
        if anomaly:
            self.notifier.notify("[!] Anomaly", f"{name}: {anomaly}",
                                f"anomaly_web_{key}", priority=4, tags="chart_with_upwards_trend")
        
        self.handle_transition(f"web_{key}", name, status, tier, latency, "web")
    
    async def monitor_wireguard(self):
        wg = self.config.get("wireguard", {})
        if not wg.get("enabled"):
            return
        
        tasks = []
        for key, ip in wg.get("peers", {}).items():
            tasks.append(self._check_wg_peer(key, ip))
        
        await asyncio.gather(*tasks, return_exceptions=True)
    
    async def _check_wg_peer(self, key: str, ip: str):
        state.checks_total += 1
        status, latency = await check_ping(ip)
        
        if status == "offline":
            state.checks_failed += 1
        else:
            self.metrics.save(f"wg_{key}", latency)
        
        wg_state = "up" if status == "online" else "down"
        self.handle_transition(f"wg_{key}", f"WG mesh → {key} ({ip})", wg_state, 1, latency, "wireguard")
    
    async def monitor_droplets(self):
        droplets = self.config.get("droplets", {})
        tasks = []
        
        for key, drop in droplets.items():
            tasks.append(self._check_droplet(key, drop))
        
        await asyncio.gather(*tasks, return_exceptions=True)
    
    async def _check_droplet(self, key: str, drop: dict):
        name = drop["name"]
        ip = drop["ip"]
        tier = drop.get("tier", 2)
        services = drop.get("services", [])
        
        state.checks_total += 1
        status, latency = await check_ping(ip)
        
        if status == "offline":
            state.checks_failed += 1
        else:
            self.metrics.save(f"droplet_{key}", latency)
        
        self.handle_transition(f"droplet_{key}_ping", name, status, tier, latency, "droplet")
        
        if status == "online":
            svc_tasks = []
            for svc in services:
                svc_tasks.append(self._check_service(f"droplet_{key}", name, ip, tier, svc))
            if svc_tasks:
                await asyncio.gather(*svc_tasks, return_exceptions=True)
    
    def update_counters(self):
        """Update global state counters from state files."""
        fleet_on = fleet_off = svc_up = svc_down = web_up = web_down = 0
        
        for f in STATE_DIR.iterdir():
            name = f.name
            val = f.read_text().strip()
            
            if name.endswith("_ping") and name.startswith("fleet_"):
                if val == "online":
                    fleet_on += 1
                elif val == "offline":
                    fleet_off += 1
            elif "_svc_" in name:
                if val == "up":
                    svc_up += 1
                else:
                    svc_down += 1
            elif name.startswith("web_"):
                if val == "up":
                    web_up += 1
                else:
                    web_down += 1
        
        state.fleet_online = fleet_on
        state.fleet_offline = fleet_off
        state.services_up = svc_up
        state.services_down = svc_down
        state.web_up = web_up
        state.web_down = web_down
    
    def check_daily_summary(self):
        summary_file = STATE_DIR / "_last_summary"
        today = datetime.date.today().isoformat()
        
        if summary_file.exists() and summary_file.read_text().strip() == today:
            return
        
        summary_file.write_text(today)
        
        msg = (f"Daily: {state.fleet_online} machines online, {state.fleet_offline} offline | "
               f"{state.services_up} services up, {state.services_down} down | "
               f"{state.web_up} web up, {state.web_down} down")
        
        self.notifier.notify("[!] AXE Daily Summary", msg, "daily_summary",
                            priority=1, tags="summary")
        self.events.log_event("system", "daily_summary", "none", "none", 0, {
            "machines_online": state.fleet_online,
            "machines_offline": state.fleet_offline,
            "services_up": state.services_up,
            "services_down": state.services_down,
            "web_up": state.web_up,
            "web_down": state.web_down,
        })
    
    async def run_cycle(self):
        """Run one complete monitoring cycle."""
        state.last_check_time = datetime.datetime.now(datetime.timezone.utc).isoformat() + "Z"
        
        await asyncio.gather(
            self.monitor_fleet(),
            self.monitor_web(),
            self.monitor_wireguard(),
            self.monitor_droplets(),
            return_exceptions=True
        )
        
        self.update_counters()
        self.check_daily_summary()
    
    async def run(self):
        log("INFO", f"Starting monitoring loop ({self.poll_interval}s interval)")
        self.notifier.notify("[AXE] AXE Fleet", f"Fleet Notify v{VERSION} started",
                            "daemon_start", priority=2, sound="Glass",
                            tags="axe,recovery", skip_observer=False)
        
        while self.running:
            try:
                await self.run_cycle()
            except Exception as e:
                log("ERROR", f"Monitor cycle failed: {e}")
            
            await asyncio.sleep(self.poll_interval)


# ─── Status CLI ───────────────────────────────────────────────
def print_status():
    print(f"═══ AXE Fleet Status (v{VERSION}) ═══")
    print()
    
    sections = {
        "Fleet Machines": ("fleet_", "_ping", {"online": "[+]", "offline": "[-]"}),
        "Web Services": ("web_", None, {"up": "[+]", "down": "[-]"}),
        "WireGuard Mesh": ("wg_", None, {"up": "[WG+]", "down": "[-]"}),
    }
    
    for title, (prefix, suffix, icons) in sections.items():
        print(f"{title}:")
        found = False
        for f in sorted(STATE_DIR.iterdir()):
            name = f.name
            if not name.startswith(prefix):
                continue
            if suffix and not name.endswith(suffix):
                continue
            
            val = f.read_text().strip()
            display_name = name.replace(prefix, "").replace(suffix or "", "")
            icon = icons.get(val, "?")
            
            # Check flap status
            flap_file = FLAP_DIR / name
            flap_extra = ""
            if flap_file.exists():
                flap_lines = flap_file.read_text().strip().split("\n")
                now = time.time()
                recent = [l for l in flap_lines if l and (now - float(l)) < 300]
                if len(recent) >= 3:
                    flap_extra = f" [!] FLAPPING ({len(recent)}x)"
            
            print(f"  {icon} {display_name}: {val}{flap_extra}")
            
            # Show services under fleet machines
            if suffix == "_ping":
                machine_key = name.replace("_ping", "")
                for sf in sorted(STATE_DIR.iterdir()):
                    if sf.name.startswith(f"{machine_key}_svc_"):
                        svc_val = sf.read_text().strip()
                        svc_name = sf.name.replace(f"{machine_key}_svc_", "")
                        svc_icon = "[+]" if svc_val == "up" else "[-]"
                        print(f"    {svc_icon} {svc_name}: {svc_val}")
            
            found = True
        
        if not found:
            print("  (no data yet)")
        print()
    
    # Droplets
    print("Droplets:")
    for f in sorted(STATE_DIR.iterdir()):
        if f.name.startswith("droplet_") and f.name.endswith("_ping"):
            val = f.read_text().strip()
            name = f.name.replace("droplet_", "").replace("_ping", "")
            icon = "[CLOUD]" if val == "online" else "[-]"
            print(f"  {icon} {name}: {val}")
    print()
    
    # Events
    print("Events (last 24h):")
    if EVENTS_LOG.exists():
        today = datetime.date.today().isoformat()
        today_events = [l for l in EVENTS_LOG.read_text().strip().split("\n") if today in l]
        print(f"  {len(today_events)} events today")
        print("  Last 5:")
        for line in today_events[-5:]:
            try:
                e = json.loads(line)
                print(f"    {e['timestamp'][:19]} {e['target']}: {e['old_state']}→{e['new_state']} ({e['event']})")
            except (json.JSONDecodeError, KeyError):
                pass
    else:
        print("  (no events yet)")
    print()
    
    # Health endpoint info
    print(f"Health endpoint: http://localhost:{HEALTH_PORT}/health")
    print(f"Metrics endpoint: http://localhost:{HEALTH_PORT}/metrics")
    print(f"Metrics files: {len(list(METRICS_DIR.glob('*.csv')))} tracked")
    print(f"Log: {LOG_DIR / 'axe-fleet-notify.log'}")


# ─── Self-Update Check ───────────────────────────────────────
def check_for_updates():
    try:
        url = "https://api.github.com/repos/memjar/axe-fleetapp/commits/main"
        req = urllib.request.Request(url)
        req.add_header("User-Agent", f"AXE-Fleet-Notify/{VERSION}")
        response = urllib.request.urlopen(req, timeout=5)
        data = json.loads(response.read().decode())
        remote_sha = data.get("sha", "")[:7]
        
        local_sha = subprocess.run(
            ["git", "-C", str(APP_DIR), "rev-parse", "--short", "HEAD"],
            capture_output=True, text=True
        ).stdout.strip()
        
        if remote_sha and local_sha and remote_sha != local_sha:
            log("INFO", f"Update available: {local_sha} → {remote_sha}")
            return remote_sha
    except Exception:
        pass
    return None


# ─── Main Entry Point ────────────────────────────────────────
def main():
    if len(sys.argv) > 1:
        cmd = sys.argv[1]
        
        if cmd == "status":
            print_status()
            sys.exit(0)
        
        elif cmd == "version":
            print(f"AXE Fleet Notify v{VERSION}")
            sys.exit(0)
        
        elif cmd == "check-update":
            update = check_for_updates()
            if update:
                print(f"Update available: {update}")
                print(f"Run: cd {APP_DIR} && git pull && bash install.sh")
            else:
                print("Up to date.")
            sys.exit(0)
        
        elif cmd == "test-notify":
            cfg = load_config()
            nm = NotificationManager(cfg)
            nm.notify("[TEST] AXE Test", "Fleet Notify test notification",
                     "test", priority=3, sound="Pop", tags="test,ok")
            print("[+] Test notification sent to all channels")
            time.sleep(2)
            sys.exit(0)
        
        elif cmd == "health":
            try:
                resp = urllib.request.urlopen(f"http://localhost:{HEALTH_PORT}/health", timeout=3)
                data = json.loads(resp.read().decode())
                print(json.dumps(data, indent=2))
            except Exception as e:
                print(f"[ERROR] Health endpoint not responding: {e}")
                sys.exit(1)
            sys.exit(0)
        
        else:
            print(f"AXE Fleet Notify v{VERSION}")
            print(f"Usage: {sys.argv[0]} [status|version|health|test-notify|check-update]")
            print(f"  (no args)      Run daemon")
            print(f"  status          Show fleet status")
            print(f"  version         Show version")
            print(f"  health          Query health endpoint")
            print(f"  test-notify     Send test notification")
            print(f"  check-update    Check for updates")
            sys.exit(0)
    
    # ─── Daemon Mode ──────────────────────────────────────────
    print(f"[AXE] AXE Fleet Notify v{VERSION}")
    
    cfg = load_config()
    acquire_pid_lock()
    
    # Signal handling
    def shutdown(signum, frame):
        log("INFO", f"═══ AXE Fleet Notify stopping (signal {signum}) ═══")
        release_pid_lock()
        sys.exit(0)
    
    signal.signal(signal.SIGTERM, shutdown)
    signal.signal(signal.SIGINT, shutdown)
    
    # Start health server
    start_health_server()
    
    # Check for updates (non-blocking)
    update = check_for_updates()
    if update:
        log("INFO", f"Update available: {update}. Run: cd {APP_DIR} && git pull")
    
    log("INFO", f"═══ AXE Fleet Notify v{VERSION} starting ═══")
    
    # Initialize AI summary engine (Carmack Pattern)
    global smart_summary
    smart_summary = SmartSummary()
    if HAS_LOCAL_MODEL:
        log("INFO", "[AXE] Local model integration active (Carmack Pattern)")
    else:
        log("INFO", "[AXE] Local model unavailable — using fallback summaries")

    # Run monitor
    monitor = FleetMonitor(cfg)
    
    try:
        asyncio.run(monitor.run())
    except KeyboardInterrupt:
        pass
    finally:
        release_pid_lock()
        log("INFO", "═══ AXE Fleet Notify stopped ═══")


if __name__ == "__main__":
    main()
