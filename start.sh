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

# ── Helper: extract clean URL (strips ANSI codes first) ──
get_sshx_url() {
  sed 's/\x1b\[[0-9;]*[a-zA-Z]//g' "$SSHX_LOG" 2>/dev/null \
    | grep -oE 'https://sshx\.io/s/[A-Za-z0-9_#]+' \
    | head -1 || true
}

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
echo "╚═══════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ─────────────────────────────────────────────────
# 1) Start HTTP server + self-ping
# ─────────────────────────────────────────────────
log "Starting control panel on port ${PORT} …"

python3 - <<'PYEND' &
import http.server, socketserver, threading, urllib.request, time, os, json, re
from datetime import datetime

PORT = int(os.environ.get("PORT", 10000))
RENDER_URL = os.environ.get("RENDER_EXTERNAL_URL", "")
PING_INTERVAL = int(os.environ.get("PING_INTERVAL", 120))
SSHX_LOG = "/tmp/sshx.log"
ANSI_RE = re.compile(r'\x1b\[[0-9;]*[a-zA-Z]')

stats = {
    "start": datetime.now().isoformat(),
    "pings": 0, "ok": 0, "fail": 0,
    "last_ping": "never", "last_status": "waiting"
}

def get_url():
    try:
        with open(SSHX_LOG) as f:
            for l in f:
                clean = ANSI_RE.sub('', l)
                if "https://sshx.io/s/" in clean:
                    s = clean.index("https://sshx.io/s/")
                    return clean[s:].strip().split()[0]
    except: pass
    return ""

def uptime():
    d = datetime.now() - datetime.fromisoformat(stats["start"])
    s = int(d.total_seconds())
    dy, s = divmod(s, 86400); h, s = divmod(s, 3600); m, s = divmod(s, 60)
    if dy: return f"{dy}d {h}h {m}m"
    if h: return f"{h}h {m}m {s}s"
    return f"{m}m {s}s"

def ping_loop():
    time.sleep(10)
    while True:
        t = RENDER_URL or f"http://localhost:{PORT}"
        try:
            r = urllib.request.urlopen(
                urllib.request.Request(f"{t}/health",
                headers={"User-Agent":"SelfPing/1.0"}), timeout=30)
            stats["ok"] += 1
            stats["last_status"] = f"OK {r.getcode()}"
        except Exception as e:
            stats["fail"] += 1
            stats["last_status"] = f"FAIL {str(e)[:40]}"
        stats["pings"] += 1
        stats["last_ping"] = datetime.now().strftime("%H:%M:%S")
        time.sleep(PING_INTERVAL)

def html():
    u = get_url(); up = uptime()
    link = f"<a href='{u}' target='_blank'>{u}</a>" if u else "<span style='color:#ff9800'>⏳ Waiting...</span>"
    return f"""<!DOCTYPE html><html><head>
<meta charset="UTF-8"><meta http-equiv="refresh" content="30">
<title>sshx Panel</title>
<style>
*{{margin:0;padding:0;box-sizing:border-box}}
body{{font-family:system-ui;background:linear-gradient(135deg,#0f0c29,#302b63,#24243e);color:#e0e0e0;min-height:100vh;padding:20px}}
.c{{max-width:800px;margin:0 auto}}
.h{{text-align:center;padding:30px 0;border-bottom:1px solid rgba(255,255,255,.1);margin-bottom:30px}}
.h h1{{font-size:2.5em;margin-bottom:10px}}
.badge{{display:inline-block;background:#00c853;color:#000;padding:5px 15px;border-radius:20px;font-weight:bold;animation:p 2s infinite}}
@keyframes p{{0%,100%{{opacity:1}}50%{{opacity:.7}}}}
.card{{background:rgba(255,255,255,.05);border:1px solid rgba(255,255,255,.1);border-radius:15px;padding:25px;margin-bottom:20px}}
.card h2{{color:#7c4dff;margin-bottom:15px}}
.url{{background:rgba(0,200,83,.1);border:2px solid #00c853;border-radius:10px;padding:20px;text-align:center;word-break:break-all}}
.url a{{color:#69f0ae;font-size:1.3em;text-decoration:none;font-weight:bold}}
.g{{display:grid;grid-template-columns:repeat(auto-fit,minmax(150px,1fr));gap:15px}}
.s{{background:rgba(255,255,255,.03);border-radius:10px;padding:15px;text-align:center}}
.s .v{{font-size:1.8em;font-weight:bold;color:#7c4dff}}
.s .l{{font-size:.85em;color:#999;margin-top:5px}}
.ps{{display:flex;align-items:center;gap:10px;padding:10px 15px;background:rgba(255,255,255,.03);border-radius:8px;margin-top:10px}}
.dot{{width:12px;height:12px;background:#00c853;border-radius:50%;animation:p 1.5s infinite}}
.info{{background:rgba(124,77,255,.1);border-left:4px solid #7c4dff;padding:15px;border-radius:0 10px 10px 0;margin-top:15px;font-size:.9em}}
footer{{text-align:center;padding:20px;color:#666;font-size:.85em}}
</style></head><body>
<div class="c">
<div class="h"><h1>🚀 sshx Panel</h1><span class="badge">● ONLINE</span></div>
<div class="card"><h2>🔗 sshx Terminal</h2><div class="url">{link}</div></div>
<div class="card"><h2>📊 Keep-Alive</h2>
<div class="g">
<div class="s"><div class="v">{up}</div><div class="l">Uptime</div></div>
<div class="s"><div class="v">{stats['pings']}</div><div class="l">Pings</div></div>
<div class="s"><div class="v">{stats['ok']}</div><div class="l">OK</div></div>
<div class="s"><div class="v">{stats['fail']}</div><div class="l">Fail</div></div>
</div>
<div class="ps"><div class="dot"></div><span>Self-ping every {PING_INTERVAL}s</span>
<span style="margin-left:auto;color:#999">Last: {stats['last_ping']} {stats['last_status']}</span></div>
<div class="info">💡 <b>No cron-job.org needed!</b> Built-in self-ping.</div>
</div>
<footer>Auto-refreshes 30s</footer></div></body></html>"""

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/health","/ping","/healthz"):
            self.send_response(200); self.send_header("Content-Type","text/plain")
            self.end_headers(); self.wfile.write(b"OK")
        elif self.path == "/status":
            self.send_response(200); self.send_header("Content-Type","application/json")
            self.end_headers(); self.wfile.write(json.dumps(stats).encode())
        else:
            self.send_response(200); self.send_header("Content-Type","text/html")
            self.end_headers(); self.wfile.write(html().encode())
    def log_message(self,*a): pass

threading.Thread(target=ping_loop, daemon=True).start()
print(f"[OK] Listening on 0.0.0.0:{PORT}", flush=True)
socketserver.TCPServer(("0.0.0.0", PORT), H).serve_forever()
PYEND

SERVER_PID=$!
sleep 2

if kill -0 "$SERVER_PID" 2>/dev/null; then
  log "Control panel running (PID: $SERVER_PID)"
else
  err "Server failed!"
  exit 1
fi

# ─────────────────────────────────────────────────
# 2) sshx
# ─────────────────────────────────────────────────
export PATH="$HOME/.sshx/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"

if ! command -v sshx &>/dev/null; then
  log "Installing sshx …"
  curl -sSf https://sshx.io/get | sh
  export PATH="$HOME/.sshx/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"
fi
log "sshx: $(which sshx)"

# ── Strip ANSI from sshx output before logging ──
> "$SSHX_LOG"
sshx --shell bash 2>&1 | sed -u 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tee "$SSHX_LOG" &
SSHX_PID=$!
log "sshx launched (PID: $SSHX_PID)"

# ─────────────────────────────────────────────────
# 3) Wait for clean URL
# ─────────────────────────────────────────────────
URL=""
for i in $(seq 1 60); do
  URL=$(get_sshx_url)
  if [[ -n "$URL" ]]; then
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}  🔗  sshx:      ${RESET}${URL}"
    echo -e "${GREEN}  🖥️  Panel:     ${RESET}https://<app>.onrender.com"
    echo -e "${GREEN}  📡  Self-ping: ${RESET}Active"
    echo -e "${GREEN}═══════════════════════════════════════════════════${RESET}"
    echo ""
    break
  fi
  sleep 1
done

[[ -z "$URL" ]] && err "Timed out" && cat "$SSHX_LOG" 2>/dev/null

# ─────────────────────────────────────────────────
# 4) Keep alive
# ─────────────────────────────────────────────────
log "All systems go ✅"

while true; do
  if ! kill -0 "$SSHX_PID" 2>/dev/null; then
    warn "sshx died — restarting …"
    > "$SSHX_LOG"
    sshx --shell bash 2>&1 | sed -u 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tee "$SSHX_LOG" &
    SSHX_PID=$!
    sleep 5
    URL=$(get_sshx_url)
    [[ -n "$URL" ]] && log "New URL: $URL"
  fi

  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    warn "Server died — restarting …"
    python3 -c "
import http.server,socketserver,os
class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        self.send_response(200);self.end_headers();self.wfile.write(b'OK')
    def log_message(self,*a):pass
socketserver.TCPServer(('0.0.0.0',int(os.environ.get('PORT',10000))),H).serve_forever()
" &
    SERVER_PID=$!
  fi

  sleep 30
done
