#!/usr/bin/env bash
# uninstall.sh — remove loom-agent-server from this machine (macOS / Linux).
#
# The mirror of install.sh / bootstrap.sh. Stops & removes the autostart service
# (systemd or launchd), deletes the installed binary, and optionally removes the
# API key and any running agent tmux sessions. Safe to run as a one-liner:
#
#   curl -fsSL https://raw.githubusercontent.com/EmpiteHenry/loom-agent-server-dist/main/uninstall.sh | bash
#
# It is self-contained (needs no bundle, no binary). Non-interactive use:
#   ASSUME_YES=1 ./uninstall.sh          # remove binary + service, KEEP the key
#   ASSUME_YES=1 PURGE=1 ./uninstall.sh  # also remove the API key + tmux sessions
#
# Knobs (env vars):
#   ASSUME_YES=1   don't prompt; take the defaults below
#   PURGE=1        with ASSUME_YES, also delete the API key + kill agent sessions
#
set -euo pipefail

BIN="loom-agent-server"
KEYFILE="$HOME/.loom-api-key"

bold() { printf '\033[1m%s\033[0m\n' "$*"; }
ok()   { printf '  \033[32m✓\033[0m %s\n' "$*"; }
warn() { printf '  \033[33m!\033[0m %s\n' "$*"; }
yesno() { # yesno "Question" "Y" -> returns 0 for yes
    local p="$1" d="${2:-Y}" a
    if [[ "${ASSUME_YES:-}" == "1" ]]; then
        # In non-interactive mode the destructive bits gate on PURGE.
        [[ "$d" =~ [Yy] ]]; return
    fi
    read -r -p "$p [$( [[ $d =~ [Yy] ]] && echo Y/n || echo y/N )]: " a </dev/tty || true
    a="${a:-$d}"; [[ "$a" =~ ^[Yy] ]]
}

bold "loom-agent-server uninstaller"
OS="$(uname -s)"
REMOVED=0

# ── 1. Stop & remove the autostart service ─────────────────────────────────
if [[ "$OS" == "Linux" ]] && command -v systemctl >/dev/null; then
    UNIT=/etc/systemd/system/loom-agent-server.service
    if systemctl list-unit-files 2>/dev/null | grep -q '^loom-agent-server\.service' || [[ -f "$UNIT" ]]; then
        sudo=""; [[ "$(id -u)" != "0" ]] && sudo="sudo"
        $sudo systemctl disable --now loom-agent-server 2>/dev/null || true
        $sudo rm -f "$UNIT"
        $sudo systemctl daemon-reload 2>/dev/null || true
        ok "removed systemd service 'loom-agent-server'"
    else
        warn "no systemd service found"
    fi
elif [[ "$OS" == "Darwin" ]]; then
    PLIST="$HOME/Library/LaunchAgents/com.empite.loom-agent-server.plist"
    if [[ -f "$PLIST" ]]; then
        launchctl unload "$PLIST" 2>/dev/null || true
        rm -f "$PLIST"
        ok "removed launchd agent 'com.empite.loom-agent-server'"
    else
        warn "no launchd agent found"
    fi
fi

# ── 2. Kill any still-running server process ───────────────────────────────
if pgrep -f "$BIN serve" >/dev/null 2>&1; then
    pkill -f "$BIN serve" 2>/dev/null || true
    ok "stopped running $BIN process(es)"
fi

# ── 3. Remove the installed binary (search the usual install dirs) ──────────
bold "Removing the binary"
for d in /usr/local/bin "$HOME/.local/bin" "$(command -v "$BIN" 2>/dev/null | xargs -I{} dirname {} 2>/dev/null)"; do
    [[ -n "$d" && -e "$d/$BIN" ]] || continue
    if [[ -w "$d" ]]; then rm -f "$d/$BIN"; else sudo rm -f "$d/$BIN"; fi
    ok "removed $d/$BIN"
    REMOVED=1
done
[[ "$REMOVED" == "1" ]] || warn "no installed $BIN binary found on PATH or in the usual dirs"

# ── 4. Optional: API key + agent tmux sessions ─────────────────────────────
PURGE_KEY=0
if [[ "${ASSUME_YES:-}" == "1" ]]; then
    [[ "${PURGE:-}" == "1" ]] && PURGE_KEY=1
elif [[ -s "$KEYFILE" ]] && yesno "Also delete the API key at $KEYFILE?" "N"; then
    PURGE_KEY=1
fi
if [[ "$PURGE_KEY" == "1" && -e "$KEYFILE" ]]; then
    rm -f "$KEYFILE"
    ok "removed $KEYFILE"
fi

if command -v tmux >/dev/null 2>&1; then
    SESSIONS="$(tmux ls 2>/dev/null | grep -o '^loom-agent-[^:]*' || true)"
    if [[ -n "$SESSIONS" ]]; then
        DO_KILL=0
        if [[ "${ASSUME_YES:-}" == "1" ]]; then
            [[ "${PURGE:-}" == "1" ]] && DO_KILL=1
        elif yesno "Kill the running agent tmux sessions?" "N"; then
            DO_KILL=1
        fi
        if [[ "$DO_KILL" == "1" ]]; then
            while read -r s; do [[ -n "$s" ]] && tmux kill-session -t "$s" 2>/dev/null || true; done <<< "$SESSIONS"
            ok "killed agent tmux sessions"
        else
            warn "left agent tmux sessions running: $(echo "$SESSIONS" | tr '\n' ' ')"
        fi
    fi
fi

# ── 5. Done ────────────────────────────────────────────────────────────────
echo
bold "Done."
[[ "$PURGE_KEY" != "1" && -s "$KEYFILE" ]] && echo "Kept your API key at $KEYFILE (delete it manually if you want it gone)."
echo "loom-agent-server has been removed. Reinstall any time with the bootstrap one-liner."
