"""
Self-pinging web control panel.
Better than cron-job.org — runs INSIDE your deploy.
"""

import http.server
import socketserver
import threading
import urllib.request
import time
import os
import json
import subprocess
from datetime import datetime, timedelta

PORT = int(os.environ.get("PORT", 10000))
RENDER_URL = os.environ.get("RENDER_EXTERNAL_URL", "")
PING_INTERVAL = int(os.environ.get("PING_INTERVAL", 120))  # seconds
SSHX_LOG = "/tmp/sshx.log"

# ── Stats tracking ──
stats = {
    "start_time": datetime.now().isoformat(),
    "pings_sent": 0,
    "pings_ok": 0,
    "pings_fail": 0,
    "last_ping": "never",
    "last_status": "waiting",
    "sshx_url": "",
    "uptime": "0s",
}


def get_sshx_url():
    """Read sshx URL from log file."""
    try:
        with open(SSHX_LOG, "r") as f:
            for line in f:
                if "https://sshx.io/s/" in line:
                    start = line.index("https://sshx.io/s/")
                    url = line[start:].strip().split()[0]
                    return url
    except Exception:
        pass
    return ""


def get_uptime():
    """Calculate uptime."""
    start = datetime.fromisoformat(stats["start_time"])
    delta = datetime.now() - start
    hours, remainder = divmod(int(delta.total_seconds()), 3600)
    minutes, seconds = divmod(remainder, 60)
    days, hours = divmod(hours, 24)
    if days > 0:
        return f"{days}d {hours}h {minutes}m"
    elif hours > 0:
        return f"{hours}h {minutes}m {seconds}s"
    else:
        return f"{minutes}m {seconds}s"


def self_ping():
    """
    Self-ping loop — pings own Render URL every PING_INTERVAL seconds.
    This replaces cron-job.org entirely.
    """
    time.sleep(10)  # wait for server to start

    while True:
        target = RENDER_URL or f"http://localhost:{PORT}"
        try:
            req = urllib.request.Request(
                f"{target}/health",
                headers={"User-Agent": "SelfPing/1.0"}
            )
            resp = urllib.request.urlopen(req, timeout=30)
            status = resp.getcode()
            stats["pings_ok"] += 1
            stats["last_status"] = f"✅ {status}"
        except Exception as e:
            stats["pings_fail"] += 1
            stats["last_status"] = f"❌ {str(e)[:50]}"

        stats["pings_sent"] += 1
        stats["last_ping"] = datetime.now().strftime("%H:%M:%S")
        stats["sshx_url"] = get_sshx_url()
        stats["uptime"] = get_uptime()

        time.sleep(PING_INTERVAL)


def multi_ping():
    """
    Bonus: ping from multiple angles to be extra safe.
    Sends requests to own URL with varied timing.
    """
    time.sleep(30)

    while True:
        target = RENDER_URL or f"http://localhost:{PORT}"
        endpoints = ["/health", "/ping", "/status", "/"]

        for ep in endpoints:
            try:
                urllib.request.urlopen(f"{target}{ep}", timeout=15)
            except Exception:
                pass
            time.sleep(15)

        time.sleep(PING_INTERVAL)


# ── HTML Dashboard ──
def dashboard_html():
    sshx_url = get_sshx_url()
    uptime = get_uptime()

    return f"""<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <meta http-equiv="refresh" content="30">
    <title>🚀 sshx Control Panel</title>
    <style>
        * {{ margin:0; padding:0; box-sizing:border-box; }}
        body {{
            font-family: 'Segoe UI', system-ui, -apple-system, sans-serif;
            background: linear-gradient(135deg, #0f0c29, #302b63, #24243e);
            color: #e0e0e0;
            min-height: 100vh;
            padding: 20px;
        }}
        .container {{ max-width: 800px; margin: 0 auto; }}
        .header {{
            text-align: center;
            padding: 30px 0;
            border-bottom: 1px solid rgba(255,255,255,0.1);
            margin-bottom: 30px;
        }}
        .header h1 {{ font-size: 2.5em; margin-bottom: 10px; }}
        .header .badge {{
            display: inline-block;
            background: #00c853;
            color: #000;
            padding: 5px 15px;
            border-radius: 20px;
            font-weight: bold;
            font-size: 0.9em;
            animation: pulse 2s infinite;
        }}
        @keyframes pulse {{
            0%, 100% {{ opacity: 1; }}
            50% {{ opacity: 0.7; }}
        }}
        .card {{
            background: rgba(255,255,255,0.05);
            border: 1px solid rgba(255,255,255,0.1);
            border-radius: 15px;
            padding: 25px;
            margin-bottom: 20px;
            backdrop-filter: blur(10px);
        }}
        .card h2 {{
            color: #7c4dff;
            margin-bottom: 15px;
            font-size: 1.3em;
        }}
        .url-box {{
            background: rgba(0,200,83,0.1);
            border: 2px solid #00c853;
            border-radius: 10px;
            padding: 20px;
            text-align: center;
            word-break: break-all;
        }}
        .url-box a {{
            color: #69f0ae;
            font-size: 1.3em;
            text-decoration: none;
            font-weight: bold;
        }}
        .url-box a:hover {{ text-decoration: underline; }}
        .stats-grid {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(180px, 1fr));
            gap: 15px;
        }}
        .stat {{
            background: rgba(255,255,255,0.03);
            border: 1px solid rgba(255,255,255,0.08);
            border-radius: 10px;
            padding: 15px;
            text-align: center;
        }}
        .stat .value {{
            font-size: 1.8em;
            font-weight: bold;
            color: #7c4dff;
        }}
        .stat .label {{
            font-size: 0.85em;
            color: #999;
            margin-top: 5px;
        }}
        .ping-status {{
            display: flex;
            align-items: center;
            gap: 10px;
            padding: 10px 15px;
            background: rgba(255,255,255,0.03);
            border-radius: 8px;
            margin-top: 10px;
        }}
        .dot {{
            width: 12px; height: 12px;
            background: #00c853;
            border-radius: 50%;
            animation: pulse 1.5s infinite;
        }}
        .info {{
            background: rgba(124,77,255,0.1);
            border-left: 4px solid #7c4dff;
            padding: 15px;
            border-radius: 0 10px 10px 0;
            margin-top: 15px;
            font-size: 0.9em;
        }}
        footer {{
            text-align: center;
            padding: 20px;
            color: #666;
            font-size: 0.85em;
        }}
    </style>
</head>
<body>
    <div class="container">
        <div class="header">
            <h1>🚀 sshx Control Panel</h1>
            <span class="badge">● ONLINE</span>
        </div>

        <div class="card">
            <h2>🔗 sshx Terminal URL</h2>
            <div class="url-box">
                {"<a href='" + sshx_url + "' target='_blank'>" + sshx_url + "</a>"
                 if sshx_url else
                 "<span style='color:#ff9800'>⏳ Waiting for sshx to start...</span>"}
            </div>
        </div>

        <div class="card">
            <h2>📊 Keep-Alive Stats</h2>
            <div class="stats-grid">
                <div class="stat">
                    <div class="value">{uptime}</div>
                    <div class="label">Uptime</div>
                </div>
                <div class="stat">
                    <div class="value">{stats['pings_sent']}</div>
                    <div class="label">Pings Sent</div>
                </div>
                <div class="stat">
                    <div class="value">{stats['pings_ok']}</div>
                    <div class="label">Successful</div>
                </div>
                <div class="stat">
                    <div class="value">{stats['pings_fail']}</div>
                    <div class="label">Failed</div>
                </div>
            </div>
            <div class="ping-status">
                <div class="dot"></div>
                <span>Self-ping active — every {PING_INTERVAL}s</span>
                <span style="margin-left:auto; color:#999;">
                    Last: {stats['last_ping']} {stats['last_status']}
                </span>
            </div>
            <div class="info">
                💡 <strong>No cron-job.org needed!</strong>
                Built-in self-ping keeps this service alive 24/7.
                Multi-endpoint pinging with automatic recovery.
            </div>
        </div>

        <div class="card">
            <h2>⚙️ Configuration</h2>
            <table style="width:100%; font-size:0.9em;">
                <tr><td style="color:#999; padding:5px 0;">Render URL</td>
                    <td>{RENDER_URL or 'auto-detect'}</td></tr>
                <tr><td style="color:#999; padding:5px 0;">Ping Interval</td>
                    <td>{PING_INTERVAL} seconds</td></tr>
                <tr><td style="color:#999; padding:5px 0;">Port</td>
                    <td>{PORT}</td></tr>
                <tr><td style="color:#999; padding:5px 0;">Started</td>
                    <td>{stats['start_time'][:19]}</td></tr>
            </table>
        </div>

        <footer>
            Auto-refreshes every 30s &bull; Self-ping replaces cron-job.org
        </footer>
    </div>
</body>
</html>"""


class Handler(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/health", "/ping", "/healthz"):
            self.send_response(200)
            self.send_header("Content-Type", "text/plain")
            self.end_headers()
            self.wfile.write(b"OK")

        elif self.path == "/status":
            stats["sshx_url"] = get_sshx_url()
            stats["uptime"] = get_uptime()
            self.send_response(200)
            self.send_header("Content-Type", "application/json")
            self.end_headers()
            self.wfile.write(json.dumps(stats, indent=2).encode())

        else:
            self.send_response(200)
            self.send_header("Content-Type", "text/html")
            self.end_headers()
            self.wfile.write(dashboard_html().encode())

    def log_message(self, format, *args):
        pass  # suppress access logs


def start_server():
    # Start self-ping threads
    threading.Thread(target=self_ping, daemon=True).start()
    threading.Thread(target=multi_ping, daemon=True).start()

    # Start HTTP server
    with socketserver.TCPServer(("0.0.0.0", PORT), Handler) as httpd:
        print(f"[✔] Control panel: http://0.0.0.0:{PORT}")
        print(f"[✔] Self-ping active (every {PING_INTERVAL}s)")
        print(f"[✔] No cron-job.org needed!")
        httpd.serve_forever()


if __name__ == "__main__":
    start_server()
