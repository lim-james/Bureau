#!/usr/bin/env bash
#
# Bureau installer.
#
# One command to make a fresh clone ready to use — including the optional voice
# ("jarvis") and overlay ("HUD") features. It:
#   1. installs the slash commands into ~/.claude/commands/ (pointed at this clone)
#   2. ensures every module script is executable
#   3. creates the runtime dir ~/.bureau/ and seeds voice.env from the template
#   4. reports what's ready and what (if anything) the user still needs to do
#
# The commands point at THIS clone as the canonical constitution, so `git pull`
# here followed by /bureau-sync in a project keeps that project up to date.
#
# Usage:
#   ./install.sh            install + report readiness
#   ./install.sh --check    ONLY report readiness (no install); add --speak to
#                           play a live voice + HUD smoke test
#   ./install.sh --help

set -euo pipefail

# Absolute path to this repo (the directory containing this script), resolving
# symlinks so it works regardless of how the script was invoked.
BUREAU_HOME="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

CLAUDE_COMMANDS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/commands"
BUREAU_DIR="${BUREAU_DIR:-$HOME/.bureau}"
VOICE_ENV="$BUREAU_DIR/voice.env"

MODE="install"; DO_SPEAK=0
for arg in "$@"; do
  case "$arg" in
    --check)  MODE="check" ;;
    --speak)  DO_SPEAK=1 ;;
    --help|-h)
      echo "usage: install.sh [--check] [--speak]"
      echo "  (no args)  install commands + set up ~/.bureau + report readiness"
      echo "  --check    report jarvis/HUD readiness only, no install"
      echo "  --speak    with --check, also play a live voice + HUD smoke test"
      exit 0 ;;
    *) echo "install.sh: unknown option '$arg' (try --help)" >&2; exit 2 ;;
  esac
done

# Report whether the optional voice (jarvis) + overlay (HUD) features are ready.
# Reused by both install and --check so there is one source of truth.
report_readiness() {
  echo
  echo "Optional voice (jarvis) + overlay (HUD) — these are WSL-on-Windows only:"
  local is_wsl=0
  if command -v wslpath >/dev/null 2>&1 \
     && [ -x '/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe' ]; then
    is_wsl=1
  fi
  if [ "$is_wsl" != "1" ]; then
    echo "  [info] not WSL-on-Windows — voice and HUD stay silent/hidden; the Bureau works fine without them."
    return 0
  fi
  echo "  [ok]   WSL + Windows PowerShell detected — the HUD will render."
  local dep
  for dep in curl python3; do
    if command -v "$dep" >/dev/null 2>&1; then
      echo "  [ok]   $dep found"
    else
      echo "  [warn] $dep missing — needed by the natural voice (voice still falls back to SAPI)"
    fi
  done
  if grep -q '^ELEVENLABS_API_KEY=.\+' "$VOICE_ENV" 2>/dev/null; then
    echo "  [ok]   ElevenLabs API key set — natural voice enabled"
  else
    echo "  [info] no ElevenLabs key yet — voice uses the robotic Windows SAPI fallback"
    echo "         add one in $VOICE_ENV to enable the natural voice"
  fi
}

# --check: report readiness (and optionally a live smoke test), then exit.
if [ "$MODE" = "check" ]; then
  echo "Bureau home:      $BUREAU_HOME"
  report_readiness
  if [ "$DO_SPEAK" = "1" ]; then
    echo
    echo "Smoke test: speaking one line and flashing the HUD…"
    BUREAU_VOICE=1 "$BUREAU_HOME/voice/speak.sh" "Bureau voice check. If you hear this, jarvis works." || \
      echo "  (voice smoke test failed — see messages above)"
    BUREAU_OVERLAY_ID=selftest "$BUREAU_HOME/overlay/overlay.sh" start "Self-test — you can close me" >/dev/null 2>&1 || true
    BUREAU_OVERLAY_ID=selftest "$BUREAU_HOME/overlay/say.sh" "HUD self-test — this window auto-closes shortly." || true
    BUREAU_OVERLAY_ID=selftest "$BUREAU_HOME/overlay/status.sh" done || true
    echo "  HUD launched (auto-fades on 'done'). If you saw it, the overlay works."
  fi
  exit 0
fi

echo "Bureau home:      $BUREAU_HOME"
echo "Installing to:    $CLAUDE_COMMANDS"

if [ ! -d "$BUREAU_HOME/docs" ] || [ ! -d "$BUREAU_HOME/commands" ]; then
  echo "error: run this script from inside a Bureau clone (docs/ and commands/ must exist)" >&2
  exit 1
fi

# --- 1. slash commands --------------------------------------------------------
mkdir -p "$CLAUDE_COMMANDS"
for src in "$BUREAU_HOME"/commands/*.md; do
  name="$(basename "$src")"
  dest="$CLAUDE_COMMANDS/$name"
  # Substitute the {{BUREAU_HOME}} placeholder with this clone's absolute path.
  sed "s#{{BUREAU_HOME}}#$BUREAU_HOME#g" "$src" > "$dest"
  echo "  installed /$(basename "$name" .md)"
done

# --- 2. make module scripts executable ----------------------------------------
# A fresh clone can land these as non-executable depending on git config; the
# docs and hooks invoke them directly, so guarantee the bit is set.
chmod +x "$BUREAU_HOME"/voice/*.sh "$BUREAU_HOME"/overlay/*.sh "$BUREAU_HOME"/hooks/*.sh 2>/dev/null || true

# --- 3. runtime dir + voice.env seed ------------------------------------------
mkdir -p "$BUREAU_DIR"
if [ ! -f "$VOICE_ENV" ] && [ -f "$BUREAU_HOME/voice/voice.env.example" ]; then
  cp "$BUREAU_HOME/voice/voice.env.example" "$VOICE_ENV"
  chmod 600 "$VOICE_ENV" 2>/dev/null || true
  echo "  seeded $VOICE_ENV (add your ElevenLabs API key to enable the natural voice)"
fi

# --- 4. environment report ("jarvis" + "HUD" readiness) -----------------------
report_readiness

echo
echo "Done. In any project directory, run:"
echo "  /bureau <your problem statement>            # or: /bureau jarvis overlay <task>"
echo "Verify the optional features any time with:  ./install.sh --check --speak"
echo
echo "To update later: 'git pull' here, re-run ./install.sh, then /bureau-sync in a project."
