#!/usr/bin/env bash
#
# Bureau voice — speak a DECISION in full ("be the voice of the model").
#
# This is the seam for briefing mode. Where narrate.sh speaks *status* ("a
# decision has been made"), decide.sh speaks *substance*: the decision itself,
# why it was made, and what it means — so you can listen instead of walking over
# to read it. It is a thin wrapper that tags the line as a decision beat (-l 4)
# and hands it to narrate.sh, which plays it ONLY when briefing mode is active.
# In every other mode (quiet/normal/verbose) this is a silent no-op, so the
# orchestrator can call it freely without checking the level first.
#
# What belongs here (and nowhere else):
#   - final decisions and the reason behind them
#   - conclusions reached, with their consequence
#   - a chosen direction over the alternatives, and why
# What does NOT belong here (use narrate.sh):
#   - status / progress ("started", "team 2 finished", "committing")
#   - mechanical sub-steps
#
# Keep each decision to 1-3 short spoken sentences: the decision, the because,
# the so-what. This is a briefing to a colleague working alongside you, not a
# document read aloud.
#
# Usage:
#   decide.sh "We're using SQLite over Postgres — single-file, zero-ops, and the write volume is tiny."
#   echo "text" | decide.sh
#
# All arming, gating, level resolution, queueing and async playback are handled
# by narrate.sh; this script only fixes the beat level at 4 (briefing/decision).

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

if [ "$#" -gt 0 ]; then
  TEXT="$*"
else
  TEXT="$(cat)"
fi
[ -z "${TEXT// }" ] && exit 0   # nothing to decide out loud

exec "$HERE/narrate.sh" -l 4 "$TEXT"
