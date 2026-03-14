#!/usr/bin/env bash
set -eo pipefail

SSHX_PID=""
SERVER_PID=""
SSHX_LOG="/tmp/sshx.log"
RESTART_FLAG="/tmp/restart_sshx"
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
echo "╔═══════════════════════════════════════════════════════╗"
echo "║   🚀  sshx Control Panel — by Md Kobir Shah  🚀      ║"
echo "╚═══════════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ─────────────────────────────────────────────────
# 1) Start HTTP server + self-ping
# ─────────────────────────────────────────────────
log "Starting control panel on port ${PORT} …"

python3 - <<'PYEND' &
import http.server, socketserver, threading, urllib.request, time, os, json, re, subprocess
from datetime import datetime

PORT = int(os.environ.get("PORT", 10000))
RENDER_URL = os.environ.get("RENDER_EXTERNAL_URL", "")
PING_INTERVAL = int(os.environ.get("PING_INTERVAL", 120))
SSHX_LOG = "/tmp/sshx.log"
RESTART_FLAG = "/tmp/restart_sshx"
ANSI_RE = re.compile(r'\x1b\[[0-9;]*[a-zA-Z]')

stats = {
    "start": datetime.now().isoformat(),
    "pings": 0, "ok": 0, "fail": 0,
    "last_ping": "never", "last_status": "waiting",
    "restarts": 0
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

def app_uptime():
    d = datetime.now() - datetime.fromisoformat(stats["start"])
    s = int(d.total_seconds())
    dy, s = divmod(s, 86400); h, s = divmod(s, 3600); m, s = divmod(s, 60)
    if dy: return f"{dy}d {h}h {m}m"
    if h: return f"{h}h {m}m {s}s"
    return f"{m}m {s}s"

def vps_uptime():
    try:
        with open("/proc/uptime") as f:
            sec = float(f.read().split()[0])
        dy, sec = divmod(int(sec), 86400)
        h, sec = divmod(sec, 3600)
        m, sec = divmod(sec, 60)
        if dy: return f"{dy}d {h}h {m}m {sec}s"
        if h: return f"{h}h {m}m {sec}s"
        return f"{m}m {sec}s"
    except: return "N/A"

def sys_info():
    info = {}
    try:
        with open("/proc/meminfo") as f:
            mem = {}
            for l in f:
                parts = l.split()
                if parts[0] in ("MemTotal:", "MemAvailable:", "MemFree:"):
                    mem[parts[0][:-1]] = int(parts[1])
            total = mem.get("MemTotal", 0)
            avail = mem.get("MemAvailable", mem.get("MemFree", 0))
            used = total - avail
            info["mem_total"] = f"{total // 1024} MB"
            info["mem_used"] = f"{used // 1024} MB"
            info["mem_pct"] = round((used / total) * 100, 1) if total else 0
    except:
        info["mem_total"] = "N/A"
        info["mem_used"] = "N/A"
        info["mem_pct"] = 0
    try:
        with open("/proc/cpuinfo") as f:
            cores = sum(1 for l in f if l.startswith("processor"))
        info["cpu_cores"] = cores
    except:
        info["cpu_cores"] = "N/A"
    try:
        load = os.getloadavg()
        info["load"] = f"{load[0]:.2f} / {load[1]:.2f} / {load[2]:.2f}"
    except:
        info["load"] = "N/A"
    try:
        r = subprocess.run(["df", "-h", "/"], capture_output=True, text=True)
        lines = r.stdout.strip().split("\n")
        if len(lines) > 1:
            parts = lines[1].split()
            info["disk_total"] = parts[1]
            info["disk_used"] = parts[2]
            info["disk_pct"] = parts[4]
        else:
            info["disk_total"] = info["disk_used"] = info["disk_pct"] = "N/A"
    except:
        info["disk_total"] = info["disk_used"] = info["disk_pct"] = "N/A"
    return info

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
        stats["last_ping"] = datetime.now().strftime("%Y-%m-%d %H:%M:%S")
        time.sleep(PING_INTERVAL)

def html():
    u = get_url()
    up = app_uptime()
    vup = vps_uptime()
    si = sys_info()
    mem_bar = min(si["mem_pct"], 100) if isinstance(si["mem_pct"], (int, float)) else 0
    disk_pct_num = int(str(si["disk_pct"]).replace("%","")) if si["disk_pct"] != "N/A" else 0

    if u:
        url_block = f"""
            <a href="{u}" target="_blank" class="sshx-link">{u}</a>
            <div class="url-actions">
                <button onclick="copyUrl()" class="btn btn-copy" id="copyBtn">📋 Copy URL</button>
                <button onclick="openUrl()" class="btn btn-open">🌐 Open Terminal</button>
                <button onclick="restartSshx()" class="btn btn-restart" id="restartBtn">🔄 Restart sshx</button>
            </div>"""
    else:
        url_block = """<div class="waiting"><div class="spinner"></div><span>Waiting for sshx to start...</span></div>"""

    return f"""<!DOCTYPE html>
<html lang="en"><head>
<meta charset="UTF-8">
<meta name="viewport" content="width=device-width,initial-scale=1.0">
<meta http-equiv="refresh" content="30">
<title>sshx Control Panel — Md Kobir Shah</title>
<style>
:root {{
    --bg-primary: #0a0a1a;
    --bg-card: rgba(255,255,255,0.03);
    --bg-card-hover: rgba(255,255,255,0.06);
    --accent: #6c5ce7;
    --accent-light: #a29bfe;
    --green: #00b894;
    --green-glow: rgba(0,184,148,0.3);
    --red: #ff7675;
    --orange: #fdcb6e;
    --text: #dfe6e9;
    --text-dim: #636e72;
    --border: rgba(255,255,255,0.06);
    --radius: 16px;
}}
* {{ margin:0; padding:0; box-sizing:border-box; }}
body {{
    font-family: 'Inter', 'SF Pro Display', system-ui, -apple-system, sans-serif;
    background: var(--bg-primary);
    color: var(--text);
    min-height: 100vh;
    overflow-x: hidden;
}}
body::before {{
    content: '';
    position: fixed;
    top: -50%; left: -50%;
    width: 200%; height: 200%;
    background: radial-gradient(circle at 30% 20%, rgba(108,92,231,0.08) 0%, transparent 50%),
                radial-gradient(circle at 70% 80%, rgba(0,184,148,0.06) 0%, transparent 50%);
    z-index: -1;
    animation: bgShift 20s ease-in-out infinite alternate;
}}
@keyframes bgShift {{
    0% {{ transform: translate(0,0) rotate(0deg); }}
    100% {{ transform: translate(-5%,5%) rotate(3deg); }}
}}
.container {{ max-width: 900px; margin: 0 auto; padding: 20px; }}

/* ── Header ── */
.header {{
    text-align: center;
    padding: 40px 20px 30px;
    position: relative;
}}
.header h1 {{
    font-size: 2.2em;
    font-weight: 800;
    background: linear-gradient(135deg, var(--accent-light), var(--green));
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    margin-bottom: 12px;
    letter-spacing: -0.5px;
}}
.header .subtitle {{
    color: var(--text-dim);
    font-size: 0.95em;
    margin-bottom: 16px;
}}
.status-badge {{
    display: inline-flex;
    align-items: center;
    gap: 8px;
    background: rgba(0,184,148,0.1);
    border: 1px solid rgba(0,184,148,0.3);
    padding: 8px 20px;
    border-radius: 30px;
    font-weight: 600;
    font-size: 0.9em;
    color: var(--green);
}}
.status-dot {{
    width: 10px; height: 10px;
    background: var(--green);
    border-radius: 50%;
    box-shadow: 0 0 10px var(--green-glow);
    animation: pulse 2s ease-in-out infinite;
}}
@keyframes pulse {{
    0%,100% {{ opacity:1; transform:scale(1); }}
    50% {{ opacity:0.6; transform:scale(0.85); }}
}}

/* ── Cards ── */
.card {{
    background: var(--bg-card);
    border: 1px solid var(--border);
    border-radius: var(--radius);
    padding: 28px;
    margin-bottom: 20px;
    transition: all 0.3s ease;
    backdrop-filter: blur(20px);
}}
.card:hover {{
    background: var(--bg-card-hover);
    border-color: rgba(255,255,255,0.1);
    transform: translateY(-2px);
    box-shadow: 0 8px 30px rgba(0,0,0,0.3);
}}
.card-title {{
    display: flex;
    align-items: center;
    gap: 10px;
    font-size: 1.15em;
    font-weight: 700;
    margin-bottom: 20px;
    color: var(--text);
}}
.card-title .icon {{
    font-size: 1.3em;
}}

/* ── sshx URL ── */
.url-box {{
    background: linear-gradient(135deg, rgba(0,184,148,0.08), rgba(108,92,231,0.08));
    border: 1px solid rgba(0,184,148,0.2);
    border-radius: 12px;
    padding: 24px;
    text-align: center;
}}
.sshx-link {{
    display: block;
    color: var(--green);
    font-size: 1.2em;
    font-weight: 700;
    text-decoration: none;
    word-break: break-all;
    padding: 10px;
    transition: all 0.2s;
}}
.sshx-link:hover {{
    color: var(--accent-light);
    text-shadow: 0 0 20px rgba(0,184,148,0.4);
}}
.url-actions {{
    display: flex;
    gap: 10px;
    justify-content: center;
    margin-top: 18px;
    flex-wrap: wrap;
}}
.btn {{
    padding: 10px 22px;
    border: 1px solid var(--border);
    border-radius: 10px;
    font-size: 0.9em;
    font-weight: 600;
    cursor: pointer;
    transition: all 0.25s ease;
    font-family: inherit;
    display: inline-flex;
    align-items: center;
    gap: 6px;
}}
.btn-copy {{
    background: rgba(108,92,231,0.15);
    color: var(--accent-light);
    border-color: rgba(108,92,231,0.3);
}}
.btn-copy:hover {{
    background: rgba(108,92,231,0.3);
    transform: translateY(-2px);
    box-shadow: 0 4px 15px rgba(108,92,231,0.3);
}}
.btn-open {{
    background: rgba(0,184,148,0.15);
    color: var(--green);
    border-color: rgba(0,184,148,0.3);
}}
.btn-open:hover {{
    background: rgba(0,184,148,0.3);
    transform: translateY(-2px);
    box-shadow: 0 4px 15px rgba(0,184,148,0.3);
}}
.btn-restart {{
    background: rgba(253,203,110,0.15);
    color: var(--orange);
    border-color: rgba(253,203,110,0.3);
}}
.btn-restart:hover {{
    background: rgba(253,203,110,0.3);
    transform: translateY(-2px);
    box-shadow: 0 4px 15px rgba(253,203,110,0.3);
}}
.btn-restart.loading {{
    opacity: 0.6;
    pointer-events: none;
}}

/* ── Waiting state ── */
.waiting {{
    display: flex;
    align-items: center;
    justify-content: center;
    gap: 12px;
    padding: 20px;
    color: var(--orange);
}}
.spinner {{
    width: 22px; height: 22px;
    border: 3px solid rgba(253,203,110,0.2);
    border-top-color: var(--orange);
    border-radius: 50%;
    animation: spin 1s linear infinite;
}}
@keyframes spin {{ to {{ transform: rotate(360deg); }} }}

/* ── Stats Grid ── */
.stats-grid {{
    display: grid;
    grid-template-columns: repeat(auto-fit, minmax(130px, 1fr));
    gap: 14px;
}}
.stat-item {{
    background: rgba(255,255,255,0.02);
    border: 1px solid var(--border);
    border-radius: 12px;
    padding: 18px 14px;
    text-align: center;
    transition: all 0.3s;
}}
.stat-item:hover {{
    background: rgba(255,255,255,0.05);
    transform: translateY(-2px);
}}
.stat-value {{
    font-size: 1.6em;
    font-weight: 800;
    background: linear-gradient(135deg, var(--accent-light), var(--green));
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
    line-height: 1.2;
}}
.stat-label {{
    font-size: 0.78em;
    color: var(--text-dim);
    margin-top: 6px;
    text-transform: uppercase;
    letter-spacing: 0.5px;
    font-weight: 600;
}}

/* ── Progress Bars ── */
.progress-row {{
    display: flex;
    align-items: center;
    gap: 12px;
    padding: 12px 0;
    border-bottom: 1px solid var(--border);
}}
.progress-row:last-child {{ border-bottom: none; }}
.progress-label {{
    width: 80px;
    font-size: 0.85em;
    color: var(--text-dim);
    font-weight: 600;
}}
.progress-bar {{
    flex: 1;
    height: 8px;
    background: rgba(255,255,255,0.05);
    border-radius: 10px;
    overflow: hidden;
}}
.progress-fill {{
    height: 100%;
    border-radius: 10px;
    transition: width 1s ease;
    background: linear-gradient(90deg, var(--green), var(--accent));
}}
.progress-fill.warn {{ background: linear-gradient(90deg, var(--orange), var(--red)); }}
.progress-value {{
    width: 70px;
    text-align: right;
    font-size: 0.85em;
    font-weight: 600;
    color: var(--text);
}}

/* ── Ping Status ── */
.ping-bar {{
    display: flex;
    align-items: center;
    gap: 10px;
    padding: 14px 18px;
    background: rgba(0,184,148,0.05);
    border: 1px solid rgba(0,184,148,0.1);
    border-radius: 10px;
    margin-top: 16px;
    font-size: 0.9em;
}}
.ping-bar .dot {{
    width: 10px; height: 10px;
    background: var(--green);
    border-radius: 50%;
    animation: pulse 1.5s infinite;
}}
.ping-info {{
    margin-left: auto;
    color: var(--text-dim);
    font-size: 0.85em;
}}

/* ── Credit Footer ── */
.credit {{
    text-align: center;
    padding: 30px 20px;
    margin-top: 10px;
}}
.credit-card {{
    display: inline-block;
    background: linear-gradient(135deg, rgba(108,92,231,0.1), rgba(0,184,148,0.1));
    border: 1px solid rgba(108,92,231,0.2);
    border-radius: 14px;
    padding: 20px 40px;
    backdrop-filter: blur(10px);
}}
.credit-label {{
    font-size: 0.75em;
    text-transform: uppercase;
    letter-spacing: 2px;
    color: var(--text-dim);
    margin-bottom: 8px;
    font-weight: 600;
}}
.credit-name {{
    font-size: 1.3em;
    font-weight: 800;
    background: linear-gradient(135deg, var(--accent-light), var(--green));
    -webkit-background-clip: text;
    -webkit-text-fill-color: transparent;
}}
.credit-role {{
    font-size: 0.8em;
    color: var(--text-dim);
    margin-top: 4px;
}}
.auto-refresh {{
    text-align: center;
    color: var(--text-dim);
    font-size: 0.8em;
    margin-top: 15px;
}}

/* ── Toast ── */
.toast {{
    position: fixed;
    bottom: 30px;
    right: 30px;
    background: var(--accent);
    color: #fff;
    padding: 14px 24px;
    border-radius: 12px;
    font-weight: 600;
    box-shadow: 0 8px 30px rgba(108,92,231,0.4);
    transform: translateY(100px);
    opacity: 0;
    transition: all 0.4s cubic-bezier(0.68,-0.55,0.265,1.55);
    z-index: 999;
}}
.toast.show {{
    transform: translateY(0);
    opacity: 1;
}}

@media (max-width: 600px) {{
    .header h1 {{ font-size: 1.6em; }}
    .sshx-link {{ font-size: 0.95em; }}
    .url-actions {{ flex-direction: column; }}
    .btn {{ width: 100%; justify-content: center; }}
    .stats-grid {{ grid-template-columns: repeat(2, 1fr); }}
}}
</style>
</head>
<body>
<div class="container">

    <!-- Header -->
    <div class="header">
        <h1>🚀 sshx Control Panel</h1>
        <p class="subtitle">Remote Terminal Management Dashboard</p>
        <div class="status-badge">
            <span class="status-dot"></span>
            ONLINE
        </div>
    </div>

    <!-- sshx URL Card -->
    <div class="card">
        <div class="card-title"><span class="icon">🔗</span> sshx Terminal</div>
        <div class="url-box">
            {url_block}
        </div>
    </div>

    <!-- VPS System Info -->
    <div class="card">
        <div class="card-title"><span class="icon">🖥️</span> VPS System Info</div>
        <div class="stats-grid" style="margin-bottom:18px">
            <div class="stat-item">
                <div class="stat-value">{vup}</div>
                <div class="stat-label">VPS Uptime</div>
            </div>
            <div class="stat-item">
                <div class="stat-value">{si['cpu_cores']}</div>
                <div class="stat-label">CPU Cores</div>
            </div>
            <div class="stat-item">
                <div class="stat-value">{si['mem_total']}</div>
                <div class="stat-label">Total RAM</div>
            </div>
            <div class="stat-item">
                <div class="stat-value">{si['disk_total']}</div>
                <div class="stat-label">Disk Total</div>
            </div>
        </div>
        <div class="progress-row">
            <span class="progress-label">Memory</span>
            <div class="progress-bar">
                <div class="progress-fill {'warn' if mem_bar > 80 else ''}" style="width:{mem_bar}%"></div>
            </div>
            <span class="progress-value">{si['mem_used']} ({si['mem_pct']}%)</span>
        </div>
        <div class="progress-row">
            <span class="progress-label">Disk</span>
            <div class="progress-bar">
                <div class="progress-fill {'warn' if disk_pct_num > 80 else ''}" style="width:{disk_pct_num}%"></div>
            </div>
            <span class="progress-value">{si['disk_used']} ({si['disk_pct']})</span>
        </div>
        <div class="progress-row">
            <span class="progress-label">Load Avg</span>
            <div style="flex:1;font-size:0.9em;color:var(--text)">{si['load']}</div>
        </div>
    </div>

    <!-- Keep-Alive Stats -->
    <div class="card">
        <div class="card-title"><span class="icon">📡</span> Self Keep-Alive</div>
        <div class="stats-grid">
            <div class="stat-item">
                <div class="stat-value">{up}</div>
                <div class="stat-label">App Uptime</div>
            </div>
            <div class="stat-item">
                <div class="stat-value">{stats['pings']}</div>
                <div class="stat-label">Total Pings</div>
            </div>
            <div class="stat-item">
                <div class="stat-value">{stats['ok']}</div>
                <div class="stat-label">Successful</div>
            </div>
            <div class="stat-item">
                <div class="stat-value">{stats['fail']}</div>
                <div class="stat-label">Failed</div>
            </div>
            <div class="stat-item">
                <div class="stat-value">{stats['restarts']}</div>
                <div class="stat-label">sshx Restarts</div>
            </div>
            <div class="stat-item">
                <div class="stat-value">{PING_INTERVAL}s</div>
                <div class="stat-label">Interval</div>
            </div>
        </div>
        <div class="ping-bar">
            <span class="dot"></span>
            <span>Self-ping active — no cron-job.org needed</span>
            <span class="ping-info">Last: {stats['last_ping']} — {stats['last_status']}</span>
        </div>
    </div>

    <!-- Developer Credit -->
    <div class="credit">
        <div class="credit-card">
            <div class="credit-label">Developer & Owner</div>
            <div class="credit-name">Md Kobir Shah</div>
            <div class="credit-role">Full Stack Developer</div>
        </div>
    </div>

    <div class="auto-refresh">Auto-refreshes every 30 seconds</div>
</div>

<div class="toast" id="toast"></div>

<script>
const sshxUrl = "{u}";

function showToast(msg, dur=3000) {{
    const t = document.getElementById('toast');
    t.textContent = msg;
    t.classList.add('show');
    setTimeout(() => t.classList.remove('show'), dur);
}}

function copyUrl() {{
    if (!sshxUrl) return;
    navigator.clipboard.writeText(sshxUrl).then(() => {{
        const btn = document.getElementById('copyBtn');
        btn.textContent = '✅ Copied!';
        showToast('URL copied to clipboard!');
        setTimeout(() => btn.textContent = '📋 Copy URL', 2000);
    }});
}}

function openUrl() {{
    if (sshxUrl) window.open(sshxUrl, '_blank');
}}

function restartSshx() {{
    const btn = document.getElementById('restartBtn');
    if (!btn) return;
    btn.classList.add('loading');
    btn.textContent = '⏳ Restarting...';
    showToast('Restarting sshx — new URL in ~10s...', 5000);

    fetch('/restart', {{ method: 'POST' }})
        .then(r => r.json())
        .then(d => {{
            showToast(d.message || 'Restart triggered!', 4000);
            setTimeout(() => location.reload(), 10000);
        }})
        .catch(() => {{
            showToast('Restart triggered — refreshing...', 3000);
            setTimeout(() => location.reload(), 10000);
        }});
}}
</script>
</body></html>"""

class H(http.server.BaseHTTPRequestHandler):
    def do_GET(self):
        if self.path in ("/health","/ping","/healthz"):
            self.send_response(200)
            self.send_header("Content-Type","text/plain")
            self.end_headers()
            self.wfile.write(b"OK")
        elif self.path == "/status":
            stats["sshx_url"] = get_url()
            stats["uptime"] = app_uptime()
            stats["vps_uptime"] = vps_uptime()
            self.send_response(200)
            self.send_header("Content-Type","application/json")
            self.end_headers()
            self.wfile.write(json.dumps(stats, indent=2).encode())
        else:
            self.send_response(200)
            self.send_header("Content-Type","text/html")
            self.end_headers()
            self.wfile.write(html().encode())

    def do_POST(self):
        if self.path == "/restart":
            stats["restarts"] += 1
            with open(RESTART_FLAG, "w") as f:
                f.write(str(time.time()))
            self.send_response(200)
            self.send_header("Content-Type","application/json")
            self.end_headers()
            self.wfile.write(json.dumps({
                "message": "sshx restart triggered! New URL in ~10 seconds.",
                "restarts": stats["restarts"]
            }).encode())
        else:
            self.send_response(404)
            self.end_headers()

    def log_message(self, *a): pass

threading.Thread(target=ping_loop, daemon=True).start()
print(f"[OK] Panel on 0.0.0.0:{PORT}", flush=True)
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

start_sshx() {
  > "$SSHX_LOG"
  sshx --shell bash 2>&1 | sed -u 's/\x1b\[[0-9;]*[a-zA-Z]//g' | tee "$SSHX_LOG" &
  SSHX_PID=$!
  log "sshx launched (PID: $SSHX_PID)"
}

start_sshx

# ─────────────────────────────────────────────────
# 3) Wait for URL
# ─────────────────────────────────────────────────
URL=""
for i in $(seq 1 60); do
  URL=$(get_sshx_url)
  if [[ -n "$URL" ]]; then
    echo ""
    echo -e "${GREEN}════��══════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}  🔗  sshx:      ${RESET}${URL}"
    echo -e "${GREEN}  🖥️  Panel:     ${RESET}https://<app>.onrender.com"
    echo -e "${GREEN}  👤  Developer: ${RESET}Md Kobir Shah"
    echo -e "${GREEN}═══════════════════════════════════════════════════${RESET}"
    echo ""
    break
  fi
  sleep 1
done

[[ -z "$URL" ]] && err "Timed out" && cat "$SSHX_LOG" 2>/dev/null

# ─────────────────────────────────────────────────
# 4) Keep alive + restart handler
# ─────────────────────────────────────────────────
log "All systems go ✅ — Developer: Md Kobir Shah"

while true; do
  # Check for restart request from web panel
  if [[ -f "$RESTART_FLAG" ]]; then
    log "🔄 Restart requested from control panel"
    rm -f "$RESTART_FLAG"

    # Kill current sshx
    if [[ -n "$SSHX_PID" ]]; then
      kill "$SSHX_PID" 2>/dev/null || true
      wait "$SSHX_PID" 2>/dev/null || true
    fi

    sleep 2
    start_sshx

    # Wait for new URL
    sleep 5
    URL=$(get_sshx_url)
    [[ -n "$URL" ]] && log "🔗 New sshx URL: $URL"
  fi

  # Auto-restart if sshx dies
  if ! kill -0 "$SSHX_PID" 2>/dev/null; then
    warn "sshx died — auto-restarting …"
    start_sshx
    sleep 5
    URL=$(get_sshx_url)
    [[ -n "$URL" ]] && log "New URL: $URL"
  fi

  # Auto-restart server if it dies
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

  sleep 5
done
