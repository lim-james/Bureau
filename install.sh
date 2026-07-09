#!/usr/bin/env bash
#
# Bureau installer.
#
# Installs the Bureau slash commands into ~/.claude/commands/ so that /bureau,
# /bureau-run, and /bureau-sync work from any project directory. The commands
# are pointed at THIS clone as the canonical constitution, so `git pull` here
# followed by /bureau-sync in a project keeps that project up to date.

set -euo pipefail

# Absolute path to this repo (the directory containing this script), resolving
# symlinks so it works regardless of how the script was invoked.
BUREAU_HOME="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"

CLAUDE_COMMANDS="${CLAUDE_CONFIG_DIR:-$HOME/.claude}/commands"

echo "Bureau home:      $BUREAU_HOME"
echo "Installing to:    $CLAUDE_COMMANDS"

if [ ! -d "$BUREAU_HOME/docs" ] || [ ! -d "$BUREAU_HOME/commands" ]; then
  echo "error: run this script from inside a Bureau clone (docs/ and commands/ must exist)" >&2
  exit 1
fi

mkdir -p "$CLAUDE_COMMANDS"

for src in "$BUREAU_HOME"/commands/*.md; do
  name="$(basename "$src")"
  dest="$CLAUDE_COMMANDS/$name"
  # Substitute the {{BUREAU_HOME}} placeholder with this clone's absolute path.
  sed "s#{{BUREAU_HOME}}#$BUREAU_HOME#g" "$src" > "$dest"
  echo "  installed /$(basename "$name" .md)"
done

echo
echo "Done. In any project directory, run:"
echo "  /bureau <your problem statement>"
echo
echo "To update later: 'git pull' here, re-run ./install.sh, then /bureau-sync in a project."
