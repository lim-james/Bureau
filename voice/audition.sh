#!/usr/bin/env bash
#
# Bureau voice — audition voices back-to-back.
#
# Speaks a sample line in each candidate voice, announcing the name first, so you
# can compare. Reuses speak.sh (same ElevenLabs + Windows playback path).
#
# Usage:
#   bash voice/audition.sh                 # audition the curated shortlist
#   bash voice/audition.sh all             # audition every voice in the list below
#   bash voice/audition.sh <id> [<id> ...] # audition specific voice_ids
#   SAMPLE="your text" bash voice/audition.sh   # custom sample line
#
# To adopt one you like, set BUREAU_VOICE_ID in ~/.bureau/voice.env.

set -uo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SAMPLE="${SAMPLE:-The Bureau is online. Agents are moving toward the task.}"

# name|voice_id  — from the account's voice library
ALL='
Sarah|EXAVITQu4vr4xnSDxMaL
Laura|FGY2WhTYpPnrIDTdsKH5
Alice|Xb7hH8MSUJpSbSDYk0k2
Matilda|XrExE9yKIg1WjnnlVkGX
Jessica|cgSgspJ2msm6clMCkdW9
Bella|hpp4J3VqNfWAUOO0d1Us
Lily|pFZP5JQG7iQjIQuC4Bku
River|SAz9YHcvj6GT2YYXdXww
George|JBFqnCBsd6RMkjVDRZzb
Brian|nPczCjzI2devNBz1zQrb
Daniel|onwK4e9ZLuTAKqWW03F9
Eric|cjVigY5qzO86Huf0OWal
Roger|CwhRBWXzGAHq8TQ4Fs17
Charlie|IKne3meq5aSn9XLyUdCD
Will|bIHbv24MWmeRgasZH58o
Chris|iP95p4xoKVk53GoZ742B
Bill|pqHfZKP75CvOlQylNhV4
Callum|N2lVS1w4EtoT3dr4eOWO
Liam|TX3LPaxmHKxFdv7VOQHJ
Harry|SOYHLrjzK2X1ezoPC6cr
Adam|pNInz6obpgDQGcFmaJgB
'

# Curated shortlist: calm / clear / JARVIS-adjacent, both genders.
SHORT='Lily River Alice Matilda Sarah Brian George Daniel'

# Resolve which voices to play.
pairs=""
if [ "$#" -gt 0 ] && [ "$1" = "all" ]; then
  pairs="$ALL"
elif [ "$#" -gt 0 ]; then
  for id in "$@"; do
    nm="$(printf '%s\n' "$ALL" | awk -F'|' -v i="$id" '$2==i{print $1}')"
    pairs="$pairs
${nm:-Voice}|$id"
  done
else
  for want in $SHORT; do
    line="$(printf '%s\n' "$ALL" | grep -i "^$want|")"
    [ -n "$line" ] && pairs="$pairs
$line"
  done
fi

# Use a here-string (no pipe) so the loop runs in THIS shell, not a subshell —
# a subshell piped into `read` can swallow output and die silently mid-run.
# Bound each voice with a timeout so one stuck PowerShell call can't wedge the
# whole audition.
# Read on fd 3, not stdin: commands inside the loop (powershell.exe via speak.sh)
# drain stdin, which would kill a normal `while read` after the first item —
# the exact "only played Sarah" bug. Redirecting each call's stdin from
# /dev/null belt-and-braces guarantees nothing steals the loop's input.
while IFS='|' read -r -u 3 name id; do
  [ -z "${id// }" ] && continue
  echo "▶ $name  ($id)"
  BUREAU_VOICE=1 BUREAU_VOICE_ID="$id" timeout 40 "$HERE/speak.sh" "This is $name. $SAMPLE" </dev/null \
    || echo "   (skipped $name — playback failed or timed out)"
  sleep 1
done 3<<< "$pairs"
echo "Done. To keep one: set BUREAU_VOICE_ID=<id> in ~/.bureau/voice.env"
