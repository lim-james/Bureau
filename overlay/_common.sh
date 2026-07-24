#!/usr/bin/env bash
#
# Bureau overlay — shared helpers. SOURCED by overlay.sh / say.sh / status.sh.
#
# Multi-session safety: every overlay is an INSTANCE keyed by an id, so several
# Bureau sessions can each have their own window without their lines, status, or
# pids colliding. The id comes from $BUREAU_OVERLAY_ID (the orchestrator sets a
# short, descriptive one derived from the task); it falls back to "default".
#
# Layout (all under ~/.bureau/, outside any repo):
#   overlay/                     instances root
#   overlay/slots.lock           lock for atomic stack-slot assignment
#   overlay/<id>/armed           presence = this instance is armed
#   overlay/<id>/feed            its summary lines (kind<TAB>text)
#   overlay/<id>/status          working | action | done | blocked
#   overlay/<id>/vis             shown | hidden
#   overlay/<id>/pid             its launched powershell.exe pid
#   overlay/<id>/title           the descriptive window title
#   overlay/<id>/slot            its stack position (0 = top)
#   overlay/<id>/height          its rendered card height (px), for height-aware stacking
#   overlay/<id>/beat            heartbeat file the HUD touches each tick; siblings
#                                use its freshness to detect a self-closed window
#                                (the pid is a WSL pid the Windows HUD can't check)
#   overlay/<id>/act.on          presence = ACTIVITY mode armed (show the mechanical
#                                ticker: edits, tests, commands as they happen)
#   overlay/<id>/act.cwd         the project dir this instance's activity belongs to,
#                                so the tool-call hook routes lines to the right window
#   overlay/<id>/act.line        the current ticker line the hook writes and the HUD
#                                renders in place ("kind<TAB>text"), newest wins

BUREAU_DIR="${BUREAU_DIR:-$HOME/.bureau}"
OVER_ROOT="$BUREAU_DIR/overlay"
SLOTS_LOCK="$OVER_ROOT/slots.lock"
# Directory these scripts live in, so helpers can invoke sibling scripts
# (e.g. auto-launching overlay.sh) regardless of the caller's cwd.
OVERLAY_BIN="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Sanitize an id to a safe directory segment: lowercase, [a-z0-9_-], trimmed,
# capped. Empty -> "default".
overlay_sanitize_id() {
  local raw; raw="$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]')"
  raw="$(printf '%s' "$raw" | tr -c 'a-z0-9_-' '-' | sed 's/-\{2,\}/-/g; s/^-//; s/-$//')"
  raw="${raw:0:40}"
  printf '%s' "${raw:-default}"
}

# Resolve the active instance id + all its paths into globals. Call once per run.
overlay_resolve() {
  OVERLAY_ID="$(overlay_sanitize_id "${BUREAU_OVERLAY_ID:-default}")"
  INST="$OVER_ROOT/$OVERLAY_ID"
  FLAG="$INST/armed"
  FEED="$INST/feed"
  STATUS="$INST/status"
  VIS="$INST/vis"
  PIDF="$INST/pid"
  TITLEF="$INST/title"
  SLOTF="$INST/slot"
  FEED_LOCK="$INST/feed.lock"
  ACT_ON="$INST/act.on"
  ACT_CWD="$INST/act.cwd"
  ACT_LINE="$INST/act.line"
}

# Resolve the instance dir that owns activity for a given project dir. The
# tool-call hook has no BUREAU_OVERLAY_ID (it fires from the harness, not the
# orchestrator), so it discovers the target by scanning armed instances for the
# one whose act.cwd matches $1. If several match (rare), the most recently armed
# wins. Prints the instance dir path, or nothing if none is armed for that cwd.
overlay_activity_target() {
  local want="$1" d best="" best_mtime=0 m
  [ -n "$want" ] || return 0
  for d in "$OVER_ROOT"/*/; do
    [ -d "$d" ] || continue
    [ -f "$d/armed" ] || continue
    [ -f "$d/act.on" ] || continue
    [ "$(cat "$d/act.cwd" 2>/dev/null)" = "$want" ] || continue
    m="$(stat -c %Y "$d/act.on" 2>/dev/null || echo 0)"
    if [ "$m" -ge "$best_mtime" ]; then best_mtime="$m"; best="$d"; fi
  done
  [ -n "$best" ] && printf '%s' "${best%/}"
}

# Is a given instance dir backed by a live launcher process?
overlay_pid_alive() {
  local pidf="$1/pid" pid
  [ -f "$pidf" ] || return 1
  pid="$(cat "$pidf" 2>/dev/null)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# Should a given instance dir be considered "present" (holds a slot, must not be
# reaped)? True if it is armed AND (its launcher is alive OR it is still
# mid-launch — armed written but pid not yet). This mirrors _taken_slots so that
# reap/repack/slot-assignment all agree, and a concurrent session's start is
# never wiped during its launch window. A dir that is disarmed, or armed with a
# dead pid, is genuinely gone and may be reaped.
overlay_present() {
  local dir="$1"
  [ -f "$dir/armed" ] || return 1
  overlay_pid_alive "$dir" && return 0
  [ ! -f "$dir/pid" ]                 # mid-launch: armed but pid not written yet
}

# This instance's own running check.
overlay_is_running() { overlay_pid_alive "$INST"; }

# Auto-launch safety net: a session may narrate (say/status) with an explicit
# BUREAU_OVERLAY_ID but forget to run `overlay.sh start` first — the window then
# never exists and the narration goes nowhere. If an id was explicitly set and no
# window is running for it, launch one. Only fires when BUREAU_OVERLAY_ID is set
# (not the implicit "default"), so a bare say/status off a real overlay stays a
# no-op. Best-effort: silent, never blocks or errors the caller.
overlay_autostart() {
  [ -n "${BUREAU_OVERLAY_ID:-}" ] || return 0     # only for explicitly-named instances
  overlay_is_running && return 0                  # already up
  [ -x "$OVERLAY_BIN/overlay.sh" ] || return 0
  # Use the existing title if one was written, else the id as a readable label.
  local title; title="$(cat "$TITLEF" 2>/dev/null)"; [ -n "$title" ] || title="$OVERLAY_ID"
  "$OVERLAY_BIN/overlay.sh" start "$title" >/dev/null 2>&1 || true
}
