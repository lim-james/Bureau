#!/usr/bin/env bash
#
# Bureau voice — the front door the orchestrator calls for a narration beat.
#
# Responsibilities that keep narration JARVIS-like instead of noisy:
#   1. GATE  — say nothing unless voice is armed for this run (the "jarvis"
#              keyword sets a per-run flag file; no flag => silent).
#   2. LEVEL — each beat carries a minimum verbosity level; it is spoken only
#              if the active level is at least that high. This is how "voice
#              more/less" is enforced by code, not by the orchestrator's whim.
#   3. QUEUE — serialize lines with flock so two beats never talk over each
#              other; lines wait their turn.
#   4. ASYNC — return immediately; the Bureau never blocks to speak.
#
# Verbosity levels:
#   1 = quiet   (default): start, done, blocked — the essentials
#   2 = normal            : + each phase transition
#   3 = verbose           : + curated sub-steps (agent N reporting, tests green…)
#   4 = briefing          : the "be the voice of the model" mode — you hear the
#                           essentials (1), phase transitions (2) and, crucially,
#                           full DECISION beats (4): the actual decision, its
#                           reason, and what it means — spoken so you can listen
#                           instead of reading. Briefing deliberately does NOT
#                           play the verbose mechanical sub-steps (3), which are
#                           noise to someone working alongside.
#
# Levels 1..3 are a monotonic ladder: a beat tagged N is spoken when ACTIVE >= N,
# so verbose hears everything below it. Level 4 (briefing) is a distinct MODE, not
# a louder verbose: it hears {1,2,4} but skips 3. Decision beats (tag 4) are heard
# ONLY in briefing — the other modes speak status ("a decision was made"), briefing
# speaks substance ("the decision is X, because Y").
#
# Usage:
#   narrate.sh "Done."                    # untagged => level 1 (always in quiet+)
#   narrate.sh -l 2 "Contract ready."     # spoken at normal, verbose
#   narrate.sh -l 3 "Researcher 3 of 6."  # spoken only at verbose
#   narrate.sh -l 4 "We chose X over Y…"  # a DECISION — spoken only in briefing
#                                         # (or use decide.sh, which tags -l 4 for you)
#
# Active level resolution (first that is set wins):
#   1. BUREAU_VOICE_LEVEL env var (explicit override)
#   2. the per-run flag file's contents (set by the "jarvis <level>" keyword)
#   3. BUREAU_VOICE_LEVEL in ~/.bureau/voice.env (persistent default)
#   4. fallback: 1 (quiet)
#
# Arming (done by the /bureau flow when the prompt contains "jarvis"):
#   echo <level> > "$BUREAU_VOICE_FLAG"   # arm for this run at a level
#   touch        "$BUREAU_VOICE_FLAG"     # arm using the default level
#   rm -f        "$BUREAU_VOICE_FLAG"     # disarm (end of run)
# Manual override for testing:
#   BUREAU_VOICE=1 BUREAU_VOICE_LEVEL=3 narrate.sh -l 3 "test line"

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUREAU_DIR="${BUREAU_DIR:-$HOME/.bureau}"
ENV_FILE="$BUREAU_DIR/voice.env"
FLAG="${BUREAU_VOICE_FLAG:-$BUREAU_DIR/voice.armed}"
LOCK="$BUREAU_DIR/voice.lock"
LOG="$BUREAU_DIR/voice.log"

mkdir -p "$BUREAU_DIR" 2>/dev/null || true

# Map a level word or number to a number; blank/unknown -> empty.
level_num() {
  case "$(printf '%s' "${1:-}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')" in
    1|quiet)    echo 1 ;;
    2|normal)   echo 2 ;;
    3|verbose)  echo 3 ;;
    4|briefing) echo 4 ;;
    *)          echo "" ;;
  esac
}

# Decide whether a beat tagged BEAT is audible at the ACTIVE level.
# Levels 1..3 are the classic ladder (audible when ACTIVE >= BEAT). Briefing (4)
# is a distinct mode, not a louder verbose: it hears essentials (1), phase
# transitions (2) and DECISION beats (4), but deliberately drops verbose
# mechanical sub-steps (3). Decision beats (4) are audible ONLY in briefing.
beat_audible() {
  local active="$1" beat="$2"
  if [ "$active" = "4" ]; then
    [ "$beat" != "3" ]              # briefing: everything except verbose mechanics
  elif [ "$beat" = "4" ]; then
    return 1                        # decision beats are briefing-only
  else
    [ "$beat" -le "$active" ]       # classic monotonic ladder
  fi
}

# --- parse optional beat level (-l N | --level N); default beat level = 1 ------
BEAT_LEVEL=1
if [ "${1:-}" = "-l" ] || [ "${1:-}" = "--level" ]; then
  BEAT_LEVEL="$(level_num "${2:-}")"; BEAT_LEVEL="${BEAT_LEVEL:-1}"
  shift 2 2>/dev/null || shift $#
fi

TEXT="$*"
[ -z "${TEXT// }" ] && exit 0

# --- GATE ----------------------------------------------------------------------
# Precedence: explicit BUREAU_VOICE env overrides; else presence of the flag file.
armed=0
case "${BUREAU_VOICE:-}" in
  1|on|true|yes) armed=1 ;;
  0|off|false|no) armed=0 ;;
  *) [ -f "$FLAG" ] && armed=1 ;;
esac
[ "$armed" = "1" ] || exit 0

# --- ACTIVE LEVEL --------------------------------------------------------------
# Load persistent default from voice.env without clobbering an explicit env var.
file_default=""
if [ -f "$ENV_FILE" ]; then
  file_default="$(level_num "$(grep -E '^BUREAU_VOICE_LEVEL=' "$ENV_FILE" 2>/dev/null | tail -1 | cut -d= -f2-)")"
fi
flag_level=""
[ -f "$FLAG" ] && flag_level="$(level_num "$(cat "$FLAG" 2>/dev/null)")"

ACTIVE="$(level_num "${BUREAU_VOICE_LEVEL:-}")"     # 1. explicit env
ACTIVE="${ACTIVE:-$flag_level}"                     # 2. per-run flag contents
ACTIVE="${ACTIVE:-$file_default}"                   # 3. persistent default
ACTIVE="${ACTIVE:-1}"                               # 4. fallback: quiet

# Suppress beats not audible at the active level (see beat_audible above).
beat_audible "$ACTIVE" "$BEAT_LEVEL" || exit 0

# --- QUEUE + ASYNC -------------------------------------------------------------
# Fire-and-forget a subshell that grabs the lock, so the caller returns now but
# lines still play strictly one-at-a-time in arrival order.
# The player is overridable for testing (BUREAU_VOICE_PLAYER); defaults to speak.sh.
PLAYER="${BUREAU_VOICE_PLAYER:-$HERE/speak.sh}"
(
  exec 9>"$LOCK"
  flock 9                       # wait for our turn
  printf '%s  [L%s] %s\n' "$(date '+%H:%M:%S' 2>/dev/null)" "$BEAT_LEVEL" "$TEXT" >> "$LOG" 2>/dev/null
  "$PLAYER" "$TEXT"
) >/dev/null 2>&1 &

disown 2>/dev/null || true
exit 0
