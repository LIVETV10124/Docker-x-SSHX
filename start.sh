#!/usr/bin/env bash
set -eo pipefail

SSHX_PID=""
SERVER_PID=""
SSHX_LOG="/tmp/sshx.log"
PORT="${PORT:-10000}"
PING_INTERVAL="${PING_INTERVAL:-120}"

GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

log()  { echo -e "${GREEN}[✔]${RESET} $*"; }
warn() { echo -e "${YELLOW}[!]${RESET} $*"; }
err()  { echo -e "${RED}[✖]${RESET} $*"; }

cleanup() {
  warn "Shutting down …"
  [[ -n "$SSHX_PID"  ]] && kill "$SSHX_PID"  2>/dev/null || true
  [[ -n "$SERVER_PID" ]] && kill "$SERVER_PID" 2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo -e "${CYAN}"
echo "╔═══════════════════════════════════════════════════╗"
echo "║   🚀  sshx + Self Keep-Alive Control Panel  🚀    ║"
echo "║   No cron-job.org needed — built-in self-ping     ║"
echo "╚═══════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ─────────────────────────────────────────────────────
# 1) Create the Python server inline (no separate file)
# ─────────────────────────────────────────────────────
cat > /tmp/server.py << 'PYEOF'
import http.server
import socketserver
import threading
import urllib.request
import time
import os
import json
from datetime import datetime

PORT = int(os.environ.get("PORT", 10000))
RENDER_URL = os.environ.get("RENDER_EXTERNAL_URL", "")
PING_INTERVAL = int(os.environ.get("PING_INTERVAL", 120))
SSHX_LOG = "/tmp/sshx.log"

stats = {
    "start_time": datetime.now().isoformat(),
    "pings_sent": 0,
    "pings_ok": 0,
    "pings_fail": 0,
    "last_ping": "never",
    "last_status": "waiting",
}

def get_sshx_url():
    try:
        with open(SSHX_LOG, "r") as f:
            for line in f:
                if "https://sshx.io/s/" in line:
                    start = line.index("https://sshx.io/s/")
                    return line[start:].strip().split()[0]
    except:
        pass
    return ""

def get_uptime():
    start = datetime.fromisoformat(stats["start_time"])
    delta = datetime.now() - start
    s = int(delta.total_seconds())
    d, s = divmod(s, 86400)
    h, s = divmod(s, 3600)
    m, s = divmod(s, 60)
    if d > 0: return f"{d}d {h}h {m}m"
    if h > 0: return f"{h}h {m}m {s}s"
    return f"{m}m {s}s"

def self_ping():
    time.sleep(10)
    while True:
        target = RENDER_URL or f"http://localhost:{PORT}"
        try:
            req = urllib.request.Request(f"{target}/health",
                    headers={"User-Agent": "SelfPing/1.0"})
            resp = urllib.request.urlopen(req, timeout=30)
            stats["pings_ok"] += 1
            stats["last_status"] = f"OK {resp.getcode()}"
        except Exception as e:
            stats["pings_fail"] += 1
            stats["last_status"] = f"FAIL {str(e)[:40]}"
        stats["pings_sent"] += 1
        stats["last_ping"] = datetime.now().strftime("%H:%M:%S")
        time.sleep(PING_INTERVAL)

def multi_ping():
    time.sleep(30)
    while True:
        target = RENDER_URL or f"http://localhost:{PORT}"
        for ep in ["/health", "/ping", "/status"]:
            try: urllib.request.urlopen(f"{target}{ep}", timeout=15)
            except: pass
            time.sleep(15)
        time.sleep(PING_INTERVAL)

def dashboard():
    url = get_sshx_url()
    up = get_uptime()
    return f"""<!DOCTYPE html>
<html><head>
<meta charset="UTF-8">
<meta http-equiv="refresh" content="30">
<title>sshx Control Panel</title>
<style>
*{{margin:0;padding:0;box-sizing:border-box}}
body{{font-family:system-ui,sans-serif;background:linear-gradient(135deg,#0f0c29,#302b63,#24243e);color:#e0e0e0;min-height:100vh;padding:20px}}
.c{{max-width:800px;margin:0 auto}}
.h{{text-align:center;padding:30px 0;border-bottom:1px solid rgba(255,255,255,.1);margin-bottom:30px}}
.h h1{{font-size:2.5em;margin-bottom:10px}}
.badge{{display:inline-block;background:#00c853;color:#000;padding:5px 15px;border-radius:20px;font-weight:bold;animation:p 2s infinite}}
@keyframes p{{0%,100%{{opacity:1}}50%{{opacity:.7}}}}
.card{{background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.1);border-radius:15px;padding:25px;margin-bottom:20px}}
.card h2{{color:#7c4dff;margin-bottom:15px}}
.url{{background:rgba(0,200,83,.1);border:2px solid #00c853;border-radius:10px;padding:20px;text-align:center;word-break:break-all}}
.url a{{color:#69f0ae;font-size:1.3em;text-decoration:none;font-weight:bold}}
.url a:hover{{text-decoration:underline}}
.g{{display:grid;grid-template-columns:repeat(auto-fit,minmax(160px,1fr));gap:15px}}
.s{{background:rgba(255,255,255,.03);border:1px solid rgba(255,255,255,.08);border-radius:10px;padding:15px;text-align:center}}
.s .v{{font-size:1.8em;font-weight:bold;color:#7c4dff}}
.s .l{{font-size:.85em;color:#999;margin-top:5px}}
.ps{{display:flex;align-items:center;gap:10px;padding:10px 15px;background:rgba(255,255,255,.03);border-radius:8px;margin-top:10px}}
.dot{{width:12px;height:12px;background:#00c853;border-radius:50%;animation:p 1.5s infinite}}
.info{{background:rgba(124,77,255,.1);border-left:4px solid #7c4dff;padding:15px;border-radius:0 10px 10px 0;margin-top:15px;font-size:.9em}}
footer{{text-align:center;padding:20px;color:#666;font-size:.85em}}
</style></head><body>
<div class="c">
<div class="h"><h1>🚀 sshx Control Panel</h1><span class="badge">● ONLINE</span></div>
<div class="card"><h2>🔗 sshx Terminal</h2><div class="url">
{"<a href='"+url+"' target='_blank'>"+url+"</a>" if url else "<span style='color:#ff9800'>⏳ Waiting for sshx...</span>"}
</div></div>
<div class="card"><h2>📊 Keep-Alive Stats</h2>
<div class="g">
<div class="s"><div class="v">{up}</div><div class="l">Uptime</div></div>
<div class="s"><div class="v">{stats['pings_sent']}</div><div class="l">Pings Sent</div></div>
<div class="s"><div class="v">{stats['pings_ok']}</div><div class="l">Successful</div></div>
<div class="s"><div class="v">{stats['pings_fail']}</div><div class="l">Failed</div></div>
</div>
<div class="ps"><div class="dot"></div>
<span>Self-ping every {PING_INTERVAL}s</span>
<span style="margin-left:auto;color:#999">Last: {stats['last_ping']} {stats['last_status']}</span>
</div>
<div class="info">💡 <b>No cron-job.org needed!</b> Built-in self-ping keeps alive 24/7.</div>
</div>
<footer>Auto-refreshes every 30s</footer>
</div></body></html>"""

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/health","/ping","/healthz"):
            self.send_response(200)
            self.send_header("Content-Type","text/plain")
            self.end_headers()
            self.wfile.write(b"OK")
        elif self.path == "/status":
            self.send_response(200)
            self.send_header("Content-Type","application/json")
            self.end_headers()
            self.wfile.write(json.dumps(stats,indent=2).encode())
        else:
            self.send_response(200)
            self.send_header("Content-Type","text/html")
            self.end_headers()
            self.wfile.write(dashboard().encode())
    def log_message(self,*a): pass

threading.Thread(target=self_ping, daemon=True).start()
threading.Thread(target=multi_ping, daemon=True).start()

print(f"[✔] Control panel on port {PORT}")
print(f"[✔] Self-ping every {PING_INTERVAL}s")
socketserver.TCPServer(("0.0.0.0", PORT), H).serve_forever()
PYEOF

log "Created server script"

# ─────────────────────────────────────────────────────
# 2) Start the control panel + self-ping FIRST
# ─────────────────────────────────────────────────────
python3 /tmp/server.py &
SERVER_PID=$!
log "Control panel running on port ${PORT} (PID: $SERVER_PID)"

# Wait a moment to make sure it's listening
sleep 2

# Verify port is open
if kill -0 "$SERVER_PID" 2>/dev/null; then
  log "Port ${PORT} is bound ✓"
else
  err "Control panel failed to start!"
  err "Falling back to simple HTTP …"
  python3 -c "
import http.server,socketserver
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200);self.end_headers();self.wfile.write(b'sshx running')
    def log_message(self,*a):pass
socketserver.TCPServer(('0.0.0.0',${PORT}),H).serve_forever()
" &
  SERVER_PID=$!
fi

# ─────────────────────────────────────────────────────
# 3) Ensure sshx is on PATH
# ─────────────────────────────────────────────────────
export PATH="$HOME/.sshx/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"

if ! command -v sshx &>/dev/null; then
  log "Installing sshx …"
  curl -sSf https://sshx.io/get | sh
  export PATH="$HOME/.sshx/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"
fi

log "sshx ready: $(which sshx)"

# ─────────────────────────────────────────────────────
# 4) Launch sshx
# ─────────────────────────────────────────────────────
> "$SSHX_LOG"
sshx --shell bash 2>&1 | tee "$SSHX_LOG" &
SSHX_PID=$!
log "sshx launched (PID: $SSHX_PID)"

# ─────────────────────────────────────────────────────
# 5) Wait for URL
# ─────────────────────────────────────────────────────
URL=""
for i in $(seq 1 60); do
  URL=$(grep -oE 'https://sshx\.io/s/[A-Za-z0-9_#/?=&-]+' "$SSHX_LOG" 2>/dev/null | head -1 || true)
  if [[ -n "$URL" ]]; then
    echo ""
    echo -e "${GREEN}════════════════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}  🔗  sshx:       ${CYAN}${URL}${RESET}"
    echo -e "${GREEN}  🖥️  Dashboard:   ${CYAN}https://<your-app>.onrender.com${RESET}"
    echo -e "${GREEN}  📡  Self-ping:   ${CYAN}Active (every ${PING_INTERVAL}s)${RESET}"
    echo -e "${GREEN}════════════════════════════════════════════════════════${RESET}"
    echo ""
    break
  fi
  sleep 1
done

[[ -z "$URL" ]] && err "Timed out" && cat "$SSHX_LOG" 2>/dev/null

# ─────────────────────────────────────────────────────
# 6) Keep alive + auto-restart
# ─────────────────────────────────────────────────────
log "All systems running ✅"

while true; do
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    warn "Control panel died — restarting …"
    python3 /tmp/server.py &
    SERVER_PID=$!
  fi

  if ! kill -0 "$SSHX_PID" 2>/dev/null; then
    warn "sshx died — restarting …"
    > "$SSHX_LOG"
    sshx --shell bash 2>&1 | tee "$SSHX_LOG" &
    SSHX_PID=$!
    sleep 5
    URL=$(grep -oE 'https://sshx\.io/s/[A-Za-z0-9_#/?=&-]+' "$SSHX_LOG" 2>/dev/null | head -1 || true)
    [[ -n "$URL" ]] && log "New sshx URL: $URL"
  fi

  sleep 30
done
