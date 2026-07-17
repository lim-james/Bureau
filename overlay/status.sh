#!/usr/bin/env bash
#
# Bureau overlay — set the HUD status indicator.
#
# The status is a persistent STATE, not a line: it says what the Bureau is doing
# right now, rendered as a coloured dot + label in the HUD corner. Distinct from
# say.sh, which appends transient lines.
#
#   working  (amber, pulsing)  — the default while the Bureau runs
#   done     (green)           — finished; nothing more is happening
#   action   (amber, pulsing)  — waiting on you (e.g. contract to approve)
#   blocked  (red, pulsing)    — stuck on something only you can resolve
#
# Gated on the overlay armed flag, so it is a safe no-op when the overlay is off.
#
# Usage:
#   status.sh working
#   status.sh action
#   status.sh done

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/_common.sh"
overlay_resolve

mkdir -p "$INST" 2>/dev/null || true

STATE="$(printf '%s' "${1:-working}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
case "$STATE" in working|done|action|blocked) : ;; *) STATE="working" ;; esac

# GATE
armed=0
case "${BUREAU_OVERLAY:-}" in
  1|on|true|yes) armed=1 ;;
  0|off|false|no) armed=0 ;;
  *) [ -f "$FLAG" ] && armed=1 ;;
esac
[ "$armed" = "1" ] || exit 0

printf '%s\n' "$STATE" > "$STATUS" 2>/dev/null || true
exit 0
