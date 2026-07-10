#!/usr/bin/env bash
#
# Bureau voice — the front door the orchestrator calls for a narration beat.
#
# Responsibilities that keep narration JARVIS-like instead of noisy:
#   1. GATE  — say nothing unless voice is armed for this run (the "jarvis"
#              keyword sets a per-run flag file; no flag => silent).
#   2. QUEUE — serialize lines with flock so two beats never talk over each
#              other; lines wait their turn.
#   3. ASYNC — return immediately; the Bureau never blocks to speak.
#
# Usage:
#   narrate.sh "Spinning up the founding panel — six specialists."
#
# Arming (done by the /bureau flow when the prompt contains "jarvis"):
#   touch "$BUREAU_VOICE_FLAG"      # arm for this run
#   rm -f "$BUREAU_VOICE_FLAG"      # disarm (end of run)
# Manual override for testing:
#   BUREAU_VOICE=1 narrate.sh "test line"     # force on
#   BUREAU_VOICE=0 narrate.sh "test line"     # force off

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUREAU_DIR="${BUREAU_DIR:-$HOME/.bureau}"
FLAG="${BUREAU_VOICE_FLAG:-$BUREAU_DIR/voice.armed}"
LOCK="$BUREAU_DIR/voice.lock"
LOG="$BUREAU_DIR/voice.log"

mkdir -p "$BUREAU_DIR" 2>/dev/null || true

# --- GATE ----------------------------------------------------------------------
# Precedence: explicit BUREAU_VOICE env overrides; else presence of the flag file.
armed=0
case "${BUREAU_VOICE:-}" in
  1|on|true|yes) armed=1 ;;
  0|off|false|no) armed=0 ;;
  *) [ -f "$FLAG" ] && armed=1 ;;
esac
[ "$armed" = "1" ] || exit 0

TEXT="$*"
[ -z "${TEXT// }" ] && exit 0

# --- QUEUE + ASYNC -------------------------------------------------------------
# Fire-and-forget a subshell that grabs the lock, so the caller returns now but
# lines still play strictly one-at-a-time in arrival order.
(
  exec 9>"$LOCK"
  flock 9                       # wait for our turn
  printf '%s  %s\n' "$(date '+%H:%M:%S' 2>/dev/null)" "$TEXT" >> "$LOG" 2>/dev/null
  "$HERE/speak.sh" "$TEXT"
) >/dev/null 2>&1 &

disown 2>/dev/null || true
exit 0
