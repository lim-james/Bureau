#!/usr/bin/env bash
#
# Bureau overlay — lifecycle controller for the glass teleprompter HUD.
#
# The overlay is the visual sibling of the voice module: a rounded, always-on-top,
# click-through window that types out a summary of each response and shows a
# status dot (working / done / action / blocked). It is a pure VIEW over a
# background Bureau run — non-interactive, opt-in, and silent unless started.
#
# Architecture (mirrors voice/):
#   overlay.sh start ─▶ arms the flag, launches hud.ps1 on the Windows side
#   say.sh / status.sh ─▶ write feed + status files (the only inputs)
#   hud.ps1            ─▶ long-lived window that renders those files; self-closes
#                         the instant the armed flag disappears
#
# Like speak.sh this is WSL-on-Windows only (it renders through Windows). On any
# other platform it prints why and exits non-zero, without touching state — the
# Bureau simply runs without a HUD.
#
# Usage:
#   overlay.sh start        # arm + launch the window (idempotent)
#   overlay.sh stop         # disarm + close the window + clean up
#   overlay.sh status       # print whether the overlay is running
#
# Files (all under ~/.bureau/, outside any repo):
#   overlay.armed   presence = armed; the HUD watches this and dies when it's gone
#   overlay.feed    the summary lines (kind<TAB>text)
#   overlay.status  one token: working|done|action|blocked
#   overlay.pid     the launched powershell.exe pid (best-effort cleanup)

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUREAU_DIR="${BUREAU_DIR:-$HOME/.bureau}"
FLAG="$BUREAU_DIR/overlay.armed"
FEED="$BUREAU_DIR/overlay.feed"
STATUS="$BUREAU_DIR/overlay.status"
VIS="$BUREAU_DIR/overlay.vis"
PIDF="$BUREAU_DIR/overlay.pid"
HUD="$HERE/hud.ps1"
PS='/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'

mkdir -p "$BUREAU_DIR" 2>/dev/null || true

preflight() {
  local missing=""
  command -v wslpath >/dev/null 2>&1 || missing="$missing wslpath"
  if [ -n "$missing" ] || [ ! -x "$PS" ]; then
    {
      echo "bureau overlay: cannot run — this feature requires WSL on Windows plus:${missing:- }"
      echo "  needs: wslpath and Windows powershell.exe (via /mnt/c)."
      echo "  On native Linux/macOS the overlay is not supported; the Bureau works fine without it."
    } >&2
    return 1
  fi
  [ -f "$HUD" ] || { echo "bureau overlay: missing hud.ps1 at $HUD" >&2; return 1; }
  return 0
}

is_running() {
  [ -f "$PIDF" ] || return 1
  local pid; pid="$(cat "$PIDF" 2>/dev/null)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

cmd_start() {
  preflight || return 1

  # Arm and initialise the view state before the window opens.
  touch "$FLAG"
  : > "$FEED"
  printf 'working\n' > "$STATUS"
  printf 'shown\n' > "$VIS"

  if is_running; then
    # already up — just ensure it's armed (above) and return
    echo "bureau overlay: already running (pid $(cat "$PIDF"))"
    return 0
  fi

  local wFeed wStatus wFlag wVis wHud
  wFeed="$(wslpath -w "$FEED")"
  wStatus="$(wslpath -w "$STATUS")"
  wFlag="$(wslpath -w "$FLAG")"
  wVis="$(wslpath -w "$VIS")"
  wHud="$(wslpath -w "$HUD")"

  # Launch detached; -WindowStyle Hidden hides the console, the WPF window shows.
  "$PS" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden \
    -File "$wHud" -Feed "$wFeed" -Status "$wStatus" -Flag "$wFlag" -Vis "$wVis" \
    >/dev/null 2>&1 &
  local pid=$!
  echo "$pid" > "$PIDF"
  disown 2>/dev/null || true
  echo "bureau overlay: started (pid $pid)"
  return 0
}

cmd_stop() {
  # Disarming makes the HUD self-close on its next tick; also kill the launcher.
  rm -f "$FLAG" 2>/dev/null || true
  if [ -f "$PIDF" ]; then
    local pid; pid="$(cat "$PIDF" 2>/dev/null)"
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    rm -f "$PIDF" 2>/dev/null || true
  fi
  rm -f "$FEED" "$STATUS" "$VIS" 2>/dev/null || true
  echo "bureau overlay: stopped"
  return 0
}

cmd_status() {
  if is_running; then echo "running (pid $(cat "$PIDF"))"; else echo "not running"; fi
}

# Slide the window out (hide) or back in (show) without quitting the process.
cmd_hide() { printf 'hidden\n' > "$VIS" 2>/dev/null || true; echo "bureau overlay: hiding"; }
cmd_show() { printf 'shown\n'  > "$VIS" 2>/dev/null || true; echo "bureau overlay: showing"; }

case "${1:-}" in
  start)  cmd_start ;;
  stop)   cmd_stop ;;
  status) cmd_status ;;
  hide)   cmd_hide ;;
  show)   cmd_show ;;
  *) echo "usage: overlay.sh {start|stop|status|hide|show}" >&2; exit 2 ;;
esac
