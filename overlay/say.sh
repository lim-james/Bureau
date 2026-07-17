#!/usr/bin/env bash
#
# Bureau overlay — push one summary line to the teleprompter HUD.
#
# This is the visual sibling of voice/narrate.sh. Where the voice speaks beats,
# this appends a one-line SUMMARY of the current response to the overlay feed,
# which the glass HUD (hud.ps1) types out. It is gated on the overlay armed flag,
# so calling it is always a safe no-op when the overlay is off.
#
# A line has a KIND (its accent colour in the HUD) and text:
#   summary   (default) — a bright summary of what just happened / the response
#   decision            — a decision or conclusion (cool accent)
#   status              — dim, low-key progress
#   action              — amber, "your input is needed"
#
# Usage:
#   say.sh "Implemented the overlay module; wiring it into the docs next."
#   say.sh -k decision "Chose a file-fed HUD over an API — no live prompt needed."
#   echo "text" | say.sh
#
# The feed is trimmed to the last N lines so it can never grow unbounded.

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/_common.sh"
overlay_resolve
LOCK="$FEED_LOCK"
KEEP=40   # keep the feed bounded; the HUD only shows the last handful

mkdir -p "$INST" 2>/dev/null || true

# --- parse optional -k/--kind KIND --------------------------------------------
KIND="summary"
if [ "${1:-}" = "-k" ] || [ "${1:-}" = "--kind" ]; then
  KIND="${2:-summary}"
  shift 2 2>/dev/null || shift $#
fi
case "$KIND" in summary|decision|status|action) : ;; *) KIND="summary" ;; esac

# --- resolve text -------------------------------------------------------------
if [ "$#" -gt 0 ]; then TEXT="$*"; else TEXT="$(cat)"; fi
# collapse newlines/tabs to spaces — one line is one entry (TAB is our delimiter)
TEXT="$(printf '%s' "$TEXT" | tr '\n\t' '  ' | sed 's/  */ /g; s/^ //; s/ $//')"
[ -z "${TEXT// }" ] && exit 0

# --- GATE: only when armed ----------------------------------------------------
armed=0
case "${BUREAU_OVERLAY:-}" in
  1|on|true|yes) armed=1 ;;
  0|off|false|no) armed=0 ;;
  *) [ -f "$FLAG" ] && armed=1 ;;
esac
[ "$armed" = "1" ] || exit 0

# --- append + trim (serialized) -----------------------------------------------
(
  exec 9>"$LOCK"
  flock 9
  printf '%s\t%s\n' "$KIND" "$TEXT" >> "$FEED" 2>/dev/null
  # trim to last $KEEP lines
  if [ -f "$FEED" ]; then
    tail -n "$KEEP" "$FEED" > "$FEED.tmp" 2>/dev/null && mv "$FEED.tmp" "$FEED" 2>/dev/null
  fi
) 2>/dev/null

exit 0
