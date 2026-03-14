#!/usr/bin/env bash
set -euo pipefail

# ─────────────────────────────────────────────
#  Render Deploy – sshx installer & launcher
# ─────────────────────────────────────────────

BOLD="\033[1m"
GREEN="\033[1;32m"
CYAN="\033[1;36m"
YELLOW="\033[1;33m"
RED="\033[1;31m"
RESET="\033[0m"

SSHX_LOG="/tmp/sshx.log"

banner() {
  echo -e "${CYAN}"
  echo "╔══════════════════════════════════════════╗"
  echo "║       🚀  SSHX on Render Deploy  🚀      ║"
  echo "╚══════════════════════════════════════════╝"
  echo -e "${RESET}"
}

log()   { echo -e "${GREEN}[✔]${RESET} $*"; }
warn()  { echo -e "${YELLOW}[!]${RESET} $*"; }
err()   { echo -e "${RED}[✖]${RESET} $*"; }

# ── Step 1: Install sshx ────────────────────
install_sshx() {
  if command -v sshx &>/dev/null; then
    log "sshx is already installed: $(which sshx)"
    return 0
  fi

  log "Installing sshx …"
  curl -sSf https://sshx.io/get | sh -s -- --yes 2>&1

  # The installer usually puts sshx in ~/.cargo/bin or /usr/local/bin
  # Make sure it's on PATH
  for p in "$HOME/.cargo/bin" "$HOME/.sshx/bin" "/usr/local/bin"; do
    if [[ -x "$p/sshx" ]]; then
      export PATH="$p:$PATH"
      break
    fi
  done

  if ! command -v sshx &>/dev/null; then
    # Fallback: search for it
    FOUND=$(find / -name "sshx" -type f -executable 2>/dev/null | head -1)
    if [[ -n "$FOUND" ]]; then
      export PATH="$(dirname "$FOUND"):$PATH"
    else
      err "sshx binary not found after install!"
      exit 1
    fi
  fi

  log "sshx installed successfully: $(which sshx)"
}

# ── Step 2: Launch sshx in background ───────
launch_sshx() {
  log "Launching sshx session …"

  # Run sshx in background, tee output to log file
  sshx --shell bash 2>&1 | tee "$SSHX_LOG" &
  SSHX_PID=$!

  log "sshx started (PID: $SSHX_PID)"
}

# ── Step 3: Wait for and display the URL ────
wait_for_url() {
  log "Waiting for sshx URL …"

  local attempts=0
  local max_attempts=60   # 60 seconds timeout
  local url=""

  while [[ $attempts -lt $max_attempts ]]; do
    if [[ -f "$SSHX_LOG" ]]; then
      url=$(grep -oE 'https://sshx\.io/s/[A-Za-z0-9_#-]+' "$SSHX_LOG" | head -1 || true)
      if [[ -n "$url" ]]; then
        echo ""
        echo -e "${BOLD}${GREEN}╔══════════════════════════════════════════════════════════╗${RESET}"
        echo -e "${BOLD}${GREEN}║                                                          ║${RESET}"
        echo -e "${BOLD}${GREEN}║   🔗  sshx is LIVE!                                      ║${RESET}"
        echo -e "${BOLD}${GREEN}║                                                          ║${RESET}"
        echo -e "${BOLD}${GREEN}║   URL: ${CYAN}${url}${GREEN}  ║${RESET}"
        echo -e "${BOLD}${GREEN}║                                                          ║${RESET}"
        echo -e "${BOLD}${GREEN}║   Open the URL above in your browser to connect.         ║${RESET}"
        echo -e "${BOLD}${GREEN}║                                                          ║${RESET}"
        echo -e "${BOLD}${GREEN}╚══════════════════════════════════════════════════════════╝${RESET}"
        echo ""
        return 0
      fi
    fi
    sleep 1
    ((attempts++))
    # Progress dots
    printf "."
  done

  echo ""
  err "Timed out waiting for sshx URL (${max_attempts}s)"
  warn "Log contents:"
  cat "$SSHX_LOG" 2>/dev/null || echo "(empty)"
  exit 1
}

# ── Step 4: Keep alive — block forever ──────
keep_alive() {
  log "Holding deploy alive. Press Ctrl+C to stop."
  echo -e "${YELLOW}[i]${RESET} sshx PID: $SSHX_PID"
  echo ""

  # Re-display URL every 5 minutes so it's visible in Render logs
  while true; do
    if ! kill -0 "$SSHX_PID" 2>/dev/null; then
      warn "sshx process died — restarting …"
      launch_sshx
      wait_for_url
    fi
    sleep 300   # heartbeat every 5 min
    url=$(grep -oE 'https://sshx\.io/s/[A-Za-z0-9_#-]+' "$SSHX_LOG" | head -1 || true)
    log "Still running | URL: ${url:-unknown}"
  done
}

# ── Cleanup on exit ─────────────────────────
cleanup() {
  echo ""
  warn "Shutting down sshx …"
  kill "$SSHX_PID" 2>/dev/null || true
  wait "$SSHX_PID" 2>/dev/null || true
  log "Done."
}
trap cleanup EXIT INT TERM

# ═══════════════════════════════════════════
#                   MAIN
# ═══════════════════════════════════════════
banner
install_sshx
launch_sshx
wait_for_url
keep_alive
