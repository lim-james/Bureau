#!/usr/bin/env bash
#
# Bureau voice — speak one line of narration to the headset.
#
# Pipeline: text -> ElevenLabs TTS (streaming mp3) -> Windows playback -> headset.
# Runs through Windows so it bypasses WSL's flaky audio and lands on the same
# device you actually wear. Verifies TLS against the corporate CA chain (no
# insecure flags). Degrades to Windows SAPI if the network/key/API ever fails,
# so the Bureau is never left unexpectedly silent.
#
# Usage:
#   speak.sh "Founding team convened."
#   echo "text" | speak.sh
#
# Config (all optional except the key): ~/.bureau/voice.env
#   ELEVENLABS_API_KEY=...        (required for the good voice)
#   BUREAU_VOICE_ID=...           (default: Jessica)
#   BUREAU_VOICE_MODEL=...        (default: eleven_turbo_v2_5 — low latency)
#   BUREAU_VOICE_CA=...           (default: ~/.bureau/corp-chain.pem if present)
#
# This script is intentionally quiet and non-fatal: narration must never crash
# or block the Bureau. All failures fall back to SAPI or, last resort, silence.

set -uo pipefail

# --- resolve the line to speak -------------------------------------------------
if [ "$#" -gt 0 ]; then
  TEXT="$*"
else
  TEXT="$(cat)"
fi
[ -z "${TEXT// }" ] && exit 0   # nothing to say

# --- preflight -----------------------------------------------------------------
# This module is WSL-specific: it plays audio by invoking Windows. On a fresh
# machine, tell the user exactly what's missing instead of hanging or dying
# silently. (Goes to stderr; the caller narrate.sh discards it, but a direct run
# or `bash -x` surfaces it.) Missing deps => exit non-zero so the fallback path
# in the caller is never fooled into thinking we spoke.
_missing=""
for _dep in curl python3 wslpath; do
  command -v "$_dep" >/dev/null 2>&1 || _missing="$_missing $_dep"
done
if [ -n "$_missing" ] || [ ! -x '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe' ]; then
  {
    echo "bureau voice: cannot run — this feature requires WSL on Windows plus:${_missing:- }"
    echo "  needs: curl, python3, wslpath, and Windows powershell.exe (via /mnt/c)."
    echo "  On native Linux/macOS the voice module is not supported; the Bureau works fine without it."
  } >&2
  exit 3
fi

# --- config --------------------------------------------------------------------
BUREAU_DIR="${BUREAU_DIR:-$HOME/.bureau}"
ENV_FILE="$BUREAU_DIR/voice.env"
[ -f "$ENV_FILE" ] && { set -a; . "$ENV_FILE"; set +a; }

VOICE_ID="${BUREAU_VOICE_ID:-cgSgspJ2msm6clMCkdW9}"        # Jessica (playful, bright, warm)
MODEL="${BUREAU_VOICE_MODEL:-eleven_turbo_v2_5}"
CA="${BUREAU_VOICE_CA:-$BUREAU_DIR/corp-chain.pem}"
PS='/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'

# --- helpers -------------------------------------------------------------------

# Convert a WSL path to a Windows path for PowerShell.
win_path() { wslpath -w "$1" 2>/dev/null; }

# Last-resort robotic fallback so a failure is still audible, not silent.
sapi_say() {
  [ -x "$PS" ] || return 1
  # Escape single quotes for the PowerShell string literal.
  local safe="${1//\'/\'\'}"
  "$PS" -NoProfile -Command \
    "Add-Type -AssemblyName System.Speech; \$s = New-Object System.Speech.Synthesis.SpeechSynthesizer; \$s.Speak('$safe')" \
    >/dev/null 2>&1
}

# Play an mp3 file through Windows' .NET MediaPlayer (native mp3, no installs,
# plays to the default Windows output = the headset). We read the clip's real
# duration and sleep exactly that long — no state-polling loop that can hang.
play_mp3_windows() {
  local wslmp3="$1"
  local winmp3; winmp3="$(win_path "$wslmp3")"
  [ -z "$winmp3" ] && return 1
  # NaturalDuration isn't ready until the media opens, so poll briefly for it
  # (bounded), then sleep the clip length + a small tail. Hard-capped so a
  # misread duration can never wedge the queue.
  "$PS" -NoProfile -Command "
    Add-Type -AssemblyName presentationCore
    \$p = New-Object System.Windows.Media.MediaPlayer
    \$p.Open([uri]'$winmp3')
    \$secs = 0.0
    for (\$i = 0; \$i -lt 20; \$i++) {
      Start-Sleep -Milliseconds 50
      if (\$p.NaturalDuration.HasTimeSpan) { \$secs = \$p.NaturalDuration.TimeSpan.TotalSeconds; break }
    }
    if (\$secs -le 0) { \$secs = 8 }              # fallback if duration unknown
    if (\$secs -gt 60) { \$secs = 60 }            # hard cap
    \$p.Play()
    Start-Sleep -Seconds ([math]::Ceiling(\$secs) + 1)
    \$p.Stop(); \$p.Close()
  " >/dev/null 2>&1
}

# --- synthesize + play ---------------------------------------------------------
speak_eleven() {
  [ -n "${ELEVENLABS_API_KEY:-}" ] || return 1

  local tmp; tmp="$(mktemp --suffix=.mp3 2>/dev/null || echo "/tmp/bureau_voice_$$.mp3")"
  local ca_args=()
  [ -f "$CA" ] && ca_args=(--cacert "$CA")

  # JSON-encode the text safely (handles quotes, newlines, unicode).
  local payload
  payload="$(TEXT="$TEXT" MODEL="$MODEL" python3 -c '
import json, os
print(json.dumps({
    "text": os.environ["TEXT"],
    "model_id": os.environ["MODEL"],
    "voice_settings": {"stability": 0.5, "similarity_boost": 0.75, "style": 0.0, "use_speaker_boost": True},
}))')" || return 1

  local code
  code="$(curl -sS --max-time 30 "${ca_args[@]}" \
    -w '%{http_code}' -o "$tmp" \
    -X POST "https://api.elevenlabs.io/v1/text-to-speech/${VOICE_ID}/stream?output_format=mp3_44100_128" \
    -H "xi-api-key: ${ELEVENLABS_API_KEY}" \
    -H "Content-Type: application/json" \
    -d "$payload" 2>/dev/null)" || { rm -f "$tmp"; return 1; }

  if [ "$code" != "200" ] || [ ! -s "$tmp" ]; then
    rm -f "$tmp"
    return 1
  fi

  play_mp3_windows "$tmp"
  local rc=$?
  rm -f "$tmp"
  return $rc
}

# --- main: try the good voice, else fall back ----------------------------------
if speak_eleven; then
  exit 0
fi
sapi_say "$TEXT"   # audible fallback; exit 0 regardless so we never break the caller
exit 0
