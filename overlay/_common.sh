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

BUREAU_DIR="${BUREAU_DIR:-$HOME/.bureau}"
OVER_ROOT="$BUREAU_DIR/overlay"
SLOTS_LOCK="$OVER_ROOT/slots.lock"

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
}

# Is a given instance dir backed by a live launcher process?
overlay_pid_alive() {
  local pidf="$1/pid" pid
  [ -f "$pidf" ] || return 1
  pid="$(cat "$pidf" 2>/dev/null)"
  [ -n "$pid" ] && kill -0 "$pid" 2>/dev/null
}

# This instance's own running check.
overlay_is_running() { overlay_pid_alive "$INST"; }
