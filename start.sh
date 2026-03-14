#!/usr/bin/env bash
set -eo pipefail

SSHX_PID=""
SSHX_LOG="/tmp/sshx.log"
PORT="${PORT:-4200}"

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
  [[ -n "$SSHX_PID" ]]   && kill "$SSHX_PID"   2>/dev/null || true
  [[ -n "$SHELL_PID" ]]   && kill "$SHELL_PID"   2>/dev/null || true
  wait 2>/dev/null || true
}
trap cleanup EXIT INT TERM

echo -e "${CYAN}"
echo "╔══════════════════════════════════════════════╗"
echo "║   🚀  Shellinabox + sshx on Render  🚀      ║"
echo "╚══════════════════════════════════════════════╝"
echo -e "${RESET}"

# ─────────────────────────────────────────
# 1) Start Shellinabox (keeps Render happy)
# ─────────────────────────────────────────
log "Starting Shellinabox on port ${PORT} …"
/usr/bin/shellinaboxd \
  --no-beep \
  -t \
  -p "$PORT" \
  -s "/:LOGIN" \
  --disable-ssl-menu &
SHELL_PID=$!
log "Shellinabox running (PID: $SHELL_PID)"

# ─────────────────────────────────────────
# 2) Make sure sshx is on PATH
# ─────────────────────────────────────────
export PATH="$HOME/.sshx/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"

if ! command -v sshx &>/dev/null; then
  log "Installing sshx …"
  curl -sSf https://sshx.io/get | sh
  export PATH="$HOME/.sshx/bin:$HOME/.cargo/bin:/usr/local/bin:$PATH"
fi

log "sshx ready: $(which sshx)"

# ─────────────────────────────────────────
# 3) Launch sshx
# ─────────────────────────────────────────
log "Launching sshx …"
> "$SSHX_LOG"
sshx --shell bash 2>&1 | tee "$SSHX_LOG" &
SSHX_PID=$!

# ─────────────────────────────────────────
# 4) Wait for sshx URL and display it
# ─────────────────────────────────────────
URL=""
for i in $(seq 1 60); do
  URL=$(grep -oE 'https://sshx\.io/s/[A-Za-z0-9_#/?=&-]+' "$SSHX_LOG" 2>/dev/null | head -1 || true)
  if [[ -n "$URL" ]]; then
    echo ""
    echo -e "${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo -e "${GREEN}  🔗  sshx URL:${RESET}  ${CYAN}${URL}${RESET}"
    echo -e "${GREEN}  🖥️  Shell:${RESET}    ${CYAN}https://<your-app>.onrender.com${RESET}"
    echo -e "${GREEN}  🔑  Login:${RESET}    root / root"
    echo -e "${CYAN}═══════════════════════════════════════════════════${RESET}"
    echo ""
    break
  fi
  sleep 1
done

if [[ -z "$URL" ]]; then
  err "Timed out waiting for sshx URL"
  cat "$SSHX_LOG" 2>/dev/null
fi

# ─────────────────────────────────────────
# 5) Keep alive — restart if anything dies
# ─────────────────────────────────────────
log "Running. Monitoring processes …"

while true; do
  # Restart shellinabox if dead
  if ! kill -0 "$SHELL_PID" 2>/dev/null; then
    warn "Shellinabox died — restarting …"
    /usr/bin/shellinaboxd --no-beep -t -p "$PORT" -s "/:LOGIN" --disable-ssl-menu &
    SHELL_PID=$!
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
