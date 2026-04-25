#!/usr/bin/env python3
"""
axe_push — AXE Fleet Push Notification Server
==============================================
Sovereign replacement for ntfy. Runs on JL2 and JL3.
Receives push requests and fires native macOS notifications + axe.observer posts.

Usage (standalone):
    python3 axe_push.py "Alert" "Edge training complete" [priority]

Usage (HTTP server on port 8088):
    python3 axe_push.py --serve

HTTP API (matches ntfy interface exactly):
    POST http://JL2:8088/push
    POST http://JL3:8088/push

    Headers:
        Title:    Notification title
        Priority: low | default | high | urgent
        Tags:     comma-separated tags

    Body: message text

    OR JSON body:
        {"title": "...", "message": "...", "priority": "high", "tags": "axe"}

AXE Technology — Sovereign Fleet Intelligence
"""

import sys
import os
import json
import subprocess
import threading
import urllib.request
from datetime import datetime, timezone
from http.server import HTTPServer, BaseHTTPRequestHandler
from pathlib import Path

PORT          = 8088
OBSERVER_URL  = "https://axe.observer/api/messages"
OBSERVER_KEY  = "_J1ra0x7W-ray8Cat_NXyFIcHUgsSRK5PnN3g0b9WUU"
LOG_FILE      = Path.home() / ".axe-fleetapp" / "logs" / "axe_push.log"
HOSTNAME      = subprocess.check_output(["hostname", "-s"], text=True).strip()

LOG_FILE.parent.mkdir(parents=True, exist_ok=True)

PRIORITY_SOUNDS = {
    "low":     "Pop",
    "default": "Glass",
    "high":    "Hero",
    "urgent":  "Sosumi",
}


def log(msg: str) -> None:
    entry = f"[{datetime.now().isoformat()}] {msg}"
    print(entry)
    with open(LOG_FILE, "a") as f:
        f.write(entry + "\n")


def osascript_notify(title: str, message: str, sound: str = "Glass") -> bool:
    """Fire a native macOS notification via osascript."""
    try:
        script = f'display notification "{message}" with title "{title}" sound name "{sound}"'
        result = subprocess.run(
            ["osascript", "-e", script],
            capture_output=True, timeout=5
        )
        return result.returncode == 0
    except Exception as e:
        log(f"osascript error: {e}")
        return False


def observer_post(title: str, message: str, priority: str = "default") -> bool:
    """Post to axe.observer for team visibility."""
    try:
        payload = json.dumps({
            "from":     f"axe-push/{HOSTNAME}",
            "to":       "team",
            "msg":      f"[{title}] {message}",
            "type":     "push-notification",
            "priority": priority,
        }).encode()
        req = urllib.request.Request(
            OBSERVER_URL,
            data=payload,
            headers={
                "Content-Type": "application/json",
                "X-API-Key":    OBSERVER_KEY,
            },
            method="POST",
        )
        with urllib.request.urlopen(req, timeout=5) as resp:
            return resp.status == 200
    except Exception:
        return False  # Non-fatal — notification already fired


def send_push(title: str, message: str, priority: str = "default",
              tags: str = "axe", post_to_observer: bool = True) -> dict:
    """
    Fire a push notification via native macOS + optionally post to axe.observer.
    This is the core function — called by both CLI and HTTP server.
    """
    sound    = PRIORITY_SOUNDS.get(priority, "Glass")
    notified = osascript_notify(title, message, sound)
    observed = observer_post(title, message, priority) if post_to_observer else False

    result = {
        "ts":        datetime.now(timezone.utc).isoformat(),
        "title":     title,
        "message":   message,
        "priority":  priority,
        "sound":     sound,
        "tags":      tags,
        "node":      HOSTNAME,
        "notified":  notified,
        "observed":  observed,
    }
    log(f"PUSH [{priority.upper()}] {title}: {message} | notified={notified} observed={observed}")
    return result


class PushHandler(BaseHTTPRequestHandler):
    """HTTP handler — mirrors ntfy's POST API exactly."""

    def do_POST(self):
        if self.path not in ("/push", "/", f"/{PORT}"):
            self.send_response(404)
            self.end_headers()
            self.wfile.write(b'{"error": "Use POST /push"}')
            return

        # Read body
        length  = int(self.headers.get("Content-Length", 0))
        body    = self.rfile.read(length) if length > 0 else b""

        # Parse: ntfy-style headers take priority, fall back to JSON body
        title    = self.headers.get("Title",    "AXE")
        priority = self.headers.get("Priority", "default")
        tags     = self.headers.get("Tags",     "axe")

        # Try JSON body
        message = ""
        try:
            data    = json.loads(body)
            message = data.get("message", data.get("msg", ""))
            title   = data.get("title", title)
            priority= data.get("priority", priority)
            tags    = data.get("tags", tags)
        except Exception:
            # Plain text body (ntfy default)
            message = body.decode("utf-8", errors="replace").strip()

        if not message:
            self.send_response(400)
            self.end_headers()
            self.wfile.write(b'{"error": "message body required"}')
            return

        # Fire in background — don't block HTTP response
        result = send_push(title, message, priority, tags)

        self.send_response(200)
        self.send_header("Content-Type", "application/json")
        self.end_headers()
        self.wfile.write(json.dumps(result).encode())

    def do_GET(self):
        """Health check."""
        if self.path in ("/health", "/"):
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps({
                "status": "ok",
                "node":   HOSTNAME,
                "port":   PORT,
                "version": "1.0.0",
            }).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, fmt, *args):
        log(f"HTTP {fmt % args}")


def serve():
    """Run the push notification HTTP server."""
    server = HTTPServer(("0.0.0.0", PORT), PushHandler)
    log(f"axe_push server started on 0.0.0.0:{PORT} (node: {HOSTNAME})")
    log(f"API: POST http://{HOSTNAME}:{PORT}/push")
    log(f"Health: GET http://{HOSTNAME}:{PORT}/health")
    try:
        server.serve_forever()
    except KeyboardInterrupt:
        log("axe_push server stopped")


def cli_push(args):
    """Send a push from the command line."""
    title    = args[0] if len(args) > 0 else "AXE"
    message  = args[1] if len(args) > 1 else "Notification"
    priority = args[2] if len(args) > 2 else "default"
    result   = send_push(title, message, priority)
    print(json.dumps(result, indent=2))
    return 0 if result["notified"] else 1


if __name__ == "__main__":
    if "--serve" in sys.argv or "--server" in sys.argv:
        serve()
    else:
        # CLI mode: axe_push.py "Title" "Message" [priority]
        sys.exit(cli_push(sys.argv[1:]))
