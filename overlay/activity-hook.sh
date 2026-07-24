#!/usr/bin/env bash
#
# Bureau overlay — ACTIVITY hook. Registered as a Claude Code PreToolUse /
# PostToolUse command hook, so the harness runs it automatically on EVERY tool
# call — edits, writes, reads, bash commands, searches, sub-agents. It turns
# each of those into a compact one-line "what's happening right now" ticker that
# the glass HUD renders in place, so you can watch the mechanical work (files
# being edited, tests running) without me having to narrate it by hand.
#
# It is PURELY OBSERVATIONAL: it reads the tool-call JSON on stdin, writes one
# small file, and ALWAYS exits 0 — it never blocks, delays, or alters a tool
# call. It is also a fast no-op unless an overlay instance has ACTIVITY mode
# armed (overlay.sh activity on) for this project dir, so leaving the hook
# registered costs nothing when the overlay is off.
#
# Claude Code stdin schema (confirmed against the hookify plugin + hook docs):
#   PreToolUse : { "tool_name": "...", "tool_input": { ... } }
#   PostToolUse: { "tool_name": "...", "tool_input": { ... }, "tool_response": {...} }
# The hook's own event name arrives as $1 ("pre" | "post") from settings.json.
#
# Working dir / project: the harness runs hooks with $CLAUDE_PROJECT_DIR set to
# the project root; we route the line to whichever armed instance claimed that
# dir via `overlay.sh activity on`.

set -uo pipefail

EVENT="${1:-post}"

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/_common.sh"

# Consume stdin regardless, so the harness's pipe never blocks on a full buffer.
INPUT="$(cat 2>/dev/null)"
[ -n "$INPUT" ] || exit 0

# Which project is this? Prefer the harness-provided dir, fall back to cwd.
CWD="${CLAUDE_PROJECT_DIR:-$PWD}"

# Find the instance that armed activity mode for this project. Cheap string scan
# of the overlay root; no jq needed to decide whether to do any work at all.
TARGET="$(overlay_activity_target "$CWD")"
[ -n "$TARGET" ] || exit 0    # activity mode not armed here — no-op

# --- parse the tool call ------------------------------------------------------
# jq is present on this host; degrade gracefully to a generic line if it's ever
# missing so the hook still never errors.
if command -v jq >/dev/null 2>&1; then
  TOOL="$(printf '%s' "$INPUT" | jq -r '.tool_name // empty' 2>/dev/null)"
else
  TOOL=""
fi
[ -n "$TOOL" ] || exit 0

# Pull a single field from tool_input via jq (empty if absent).
_in() { printf '%s' "$INPUT" | jq -r ".tool_input.$1 // empty" 2>/dev/null; }

# Shorten a path to its basename for the ticker (full paths are too wide for the
# glass card). Leaves non-paths untouched.
_base() { case "$1" in */*) printf '%s' "${1##*/}";; *) printf '%s' "$1";; esac; }

# Compress a bash command to a readable gist: the first meaningful statement,
# with a leading directory-change prelude dropped so the verb the user cares
# about leads. Newlines are treated as statement separators (like ';').
_cmd_gist() {
  local c="$1"
  # newlines -> "; " so each line is its own statement, then collapse spaces
  c="$(printf '%s' "$c" | tr '\n' ';' | sed 's/  */ /g; s/^ *//; s/ *$//')"
  # drop a leading "cd X &&|;|" prelude (repeat once in case of "cd a && cd b")
  c="$(printf '%s' "$c" | sed -E 's/^cd[[:space:]]+[^&;|]+[[:space:]]*([&;|]{1,2})[[:space:]]*//')"
  # keep just the first statement for the ticker (drop trailing &&, ;, | chains)
  c="$(printf '%s' "$c" | sed -E 's/[[:space:]]*([&;|]{1,2}).*$//')"
  printf '%s' "$c" | sed 's/^ *//; s/ *$//'
}

# Truncate to keep the ticker to one tidy line.
_clip() { local s="$1" n="${2:-52}"; if [ "${#s}" -gt "$n" ]; then printf '%s…' "${s:0:$n}"; else printf '%s' "$s"; fi; }

# Map the tool call to (kind, glyph, verb, detail). KIND drives the accent colour
# in the HUD, matching say.sh's vocabulary plus an "activity" default.
KIND="activity"; GLYPH="•"; VERB=""; DETAIL=""
case "$TOOL" in
  Edit|MultiEdit) GLYPH="✎"; VERB="editing";  DETAIL="$(_base "$(_in file_path)")" ;;
  Write)          GLYPH="✎"; VERB="writing";  DETAIL="$(_base "$(_in file_path)")" ;;
  Read)           GLYPH="▤"; VERB="reading";  DETAIL="$(_base "$(_in file_path)")" ;;
  NotebookEdit)   GLYPH="✎"; VERB="editing";  DETAIL="$(_base "$(_in notebook_path)")" ;;
  Grep)           GLYPH="⌕"; VERB="searching"; DETAIL="$(_clip "$(_in pattern)" 32)" ;;
  Glob)           GLYPH="⌕"; VERB="globbing";  DETAIL="$(_clip "$(_in pattern)" 32)" ;;
  Bash)           GLYPH="❯"; VERB="running";   DETAIL="$(_clip "$(_cmd_gist "$(_in command)")" 48)" ;;
  Task|Agent)     GLYPH="◆"; VERB="delegating"; DETAIL="$(_clip "$(_in description)" 40)" ;;
  WebFetch)       GLYPH="🌐"; VERB="fetching";  DETAIL="$(_clip "$(_in url)" 40)" ;;
  WebSearch)      GLYPH="⌕"; VERB="researching"; DETAIL="$(_clip "$(_in query)" 40)" ;;
  TodoWrite|TaskCreate|TaskUpdate) GLYPH="☑"; VERB="planning"; DETAIL="" ;;
  *)              GLYPH="•"; VERB="$(printf '%s' "$TOOL" | tr '[:upper:]' '[:lower:]')"; DETAIL="" ;;
esac

# On the POST event, a Bash command that failed is worth flagging red. We only
# have the tool_response here; a non-zero-ish signal flips the kind to "blocked".
if [ "$EVENT" = "post" ] && [ "$TOOL" = "Bash" ]; then
  RESP="$(printf '%s' "$INPUT" | jq -r '.tool_response | (.stderr // "") + " " + ((.interrupted // false)|tostring)' 2>/dev/null)"
  case "$RESP" in *rror*|*ailed*|*" true"*) KIND="warn" ;; esac
fi

# Compose the line. Pre and post render the same verb; the HUD's spinner conveys
# "in flight", so we don't spam a separate "done" line per call.
if [ -n "$DETAIL" ]; then TEXT="$GLYPH $VERB $DETAIL"; else TEXT="$GLYPH $VERB"; fi
TEXT="$(printf '%s' "$TEXT" | tr '\n\t' '  ' | sed 's/  */ /g; s/^ //; s/ $//')"
[ -z "${TEXT// }" ] && exit 0

# --- write the ticker line (last-writer-wins; single line, updated in place) --
# No lock needed: this is a single small atomic-ish write of one line, and the
# HUD only ever reads the latest. Write to a temp then mv for atomicity.
printf '%s\t%s\n' "$KIND" "$TEXT" > "$TARGET/act.line.tmp" 2>/dev/null \
  && mv "$TARGET/act.line.tmp" "$TARGET/act.line" 2>/dev/null || true

exit 0
