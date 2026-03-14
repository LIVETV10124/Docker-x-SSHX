#!/usr/bin/env bash
set -eo pipefail

SSHX_PID=""
SERVER_PID=""
SSHX_LOG="/tmp/sshx.log"
PORT="${PORT:-10000}"

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
  [[ -n "$SSHX_PID"   ]] && kill "$SSHX_PID"   2>/dev/null || true
  [[ -n "$SERVER_PID"  ]] && kill "$SERVER_PID"  2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo -e "${CYAN}"
echo "╔══════���════════════════════════════════════════════╗"
echo "║   🚀  sshx + Self Keep-Alive Control Panel  🚀    ║"
echo "║   No cron-job.org needed — built-in self-ping     ║"
echo "╚═══════════════════════════════════════════════════╝"
echo -e "${RESET}"

# ── 1) Start web control panel + self-ping ──
log "Starting control panel + self-ping on port ${PORT} …"
python3 /app/server.py &
SERVER_PID=$!
log "Control panel running (PID: $SERVER_PID)"

# ── 2) Ensure sshx is on PATH ──
export PATH="$HOME/.sshx/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"

if ! command -v sshx &>/dev/null; then
  log "Installing sshx …"
  curl -sSf https://sshx.io/get | sh
  export PATH="$HOME/.sshx/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"
fi

log "sshx ready: $(which sshx)"

# ── 3) Launch sshx ──
> "$SSHX_LOG"
sshx --shell bash 2>&1 | tee "$SSHX_LOG" &
SSHX_PID=$!
log "sshx launched (PID: $SSHX_PID)"

# ── 4) Wait for URL ──
URL=""
for i in $(seq 1 60); do
  URL=$(grep -oE 'https://sshx\.io/s/[A-Za-z0-9_#/?=&-]+' "$SSHX_LOG" 2>/dev/null | head -1 || true)
  if [[ -n "$URL" ]]; then
    echo ""
    echo -e "${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}  🔗  sshx:      ${CYAN}${URL}${RESET}"
    echo -e "${GREEN}  🖥️  Dashboard:  ${CYAN}https://<your-app>.onrender.com${RESET}"
    echo -e "${GREEN}  📡  Self-ping:  ${CYAN}Active (every ${PING_INTERVAL:-120}s)${RESET}"
    echo -e "${GREEN}═══════════════════════════════════════════════════════${RESET}"
    echo ""
    break
  fi
  sleep 1
done

[[ -z "$URL" ]] && err "Timed out waiting for sshx URL" && cat "$SSHX_LOG" 2>/dev/null

# ── 5) Keep alive + auto-restart ──
log "Monitoring processes …"
log "✅ Self-ping replaces cron-job.org — nothing external needed!"

while true; do
  # Restart control panel if dead
  if ! kill -0 "$SERVER_PID" 2>/dev/null; then
    warn "Control panel died — restarting …"
    python3 /app/server.py &
    SERVER_PID=$!
  fi

  # Restart sshx if dead
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
