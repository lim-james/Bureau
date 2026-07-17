#!/usr/bin/env bash
#
# Bureau overlay — lifecycle controller for the glass teleprompter HUD.
#
# The overlay is the visual sibling of the voice module: a rounded, always-on-top,
# click-through window that types out a summary of each response and shows a
# status dot (working / done / action / blocked). It is a pure VIEW over a
# background Bureau run — non-interactive, opt-in, and silent unless started.
#
# MULTI-SESSION: every overlay is an INSTANCE keyed by $BUREAU_OVERLAY_ID, so
# several Bureau sessions each get their OWN window — their own feed, status, pid,
# and a descriptive title — and the windows auto-STACK down the right edge (each
# takes the lowest free slot). Nothing collides. See _common.sh for the layout.
#
# Like speak.sh this is WSL-on-Windows only (it renders through Windows). On any
# other platform it prints why and exits non-zero, without touching state — the
# Bureau simply runs without a HUD.
#
# Usage:
#   BUREAU_OVERLAY_ID=export-pipeline \
#     overlay.sh start "Export pipeline — latency work"   # arm + launch a window
#   overlay.sh stop          # disarm + close THIS instance's window + clean up
#   overlay.sh status        # is THIS instance running?
#   overlay.sh hide|show     # slide THIS instance out / back in
#   overlay.sh list          # list all instances (id, slot, pid, title)
#   overlay.sh stop-all      # stop every instance

set -uo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
. "$HERE/_common.sh"
overlay_resolve

HUD="$HERE/hud.ps1"
PS='/mnt/c/Windows/System32/WindowsPowerShell/v1.0/powershell.exe'
SLOT_MAX=8      # how many windows can stack before we wrap back to slot 0

mkdir -p "$OVER_ROOT" 2>/dev/null || true

preflight() {
  local missing=""
  command -v wslpath >/dev/null 2>&1 || missing="$missing wslpath"
  if [ -n "$missing" ] || [ ! -x "$PS" ]; then
    {
      echo "bureau overlay: cannot run — this feature requires WSL on Windows plus:${missing:- }"
      echo "  needs: wslpath and Windows powershell.exe (via /mnt/c)."
      echo "  On native Linux/macOS the overlay is not supported; the Bureau works fine without it."
    } >&2
    return 1
  fi
  [ -f "$HUD" ] || { echo "bureau overlay: missing hud.ps1 at $HUD" >&2; return 1; }
  return 0
}

# Which stack slots are currently held by OTHER instances (excluding this one).
# A slot is "taken" if the instance is armed AND is either alive or still
# mid-launch (armed set but pid file not written yet). A crashed instance whose
# pid is dead does NOT hold its slot, so slots are reclaimed. Prints one per line.
_taken_slots() {
  local d id
  for d in "$OVER_ROOT"/*/; do
    [ -d "$d" ] || continue
    id="$(basename "$d")"
    [ "$id" = "$OVERLAY_ID" ] && continue
    [ -f "$d/armed" ] || continue
    [ -f "$d/slot" ] || continue
    if overlay_pid_alive "$OVER_ROOT/$id"; then
      cat "$d/slot" 2>/dev/null            # alive
    elif [ ! -f "$d/pid" ]; then
      cat "$d/slot" 2>/dev/null            # mid-launch (pid not written yet)
    fi
  done
}

# Pick the lowest free slot [0..SLOT_MAX-1] given the currently-taken set.
_pick_slot() {
  local slot=0 taken="$1"
  while [ "$slot" -lt "$SLOT_MAX" ]; do
    case " $taken " in *" $slot "*) slot=$((slot+1));; *) break;; esac
  done
  # Past SLOT_MAX (many simultaneous sessions) the screen is full; land on the
  # last slot rather than slot 0, so we don't overlap the primary (top) window.
  [ "$slot" -ge "$SLOT_MAX" ] && slot=$((SLOT_MAX - 1))
  printf '%s' "$slot"
}

# Remove instance dirs whose window is gone (auto-faded on 'done', self-closed on
# disarm, or crashed) — i.e. disarmed OR dead pid. These closed themselves without
# going through cmd_stop, so their dirs linger; reap them so the stack is accurate.
_reap() {
  local d id
  for d in "$OVER_ROOT"/*/; do
    [ -d "$d" ] || continue
    id="$(basename "$d")"
    if [ ! -f "$d/armed" ] || ! overlay_pid_alive "$OVER_ROOT/$id"; then
      rm -rf "$d" 2>/dev/null || true
    fi
  done
}

# Re-pack live instances to contiguous slots 0,1,2,… preserving their visual
# order (by current slot). Each instance's HUD polls its slot file and glides to
# the new row, so closing a middle window makes the ones below slide up to fill
# the gap. Run under the slots lock.
_repack() {
  exec 8>"$SLOTS_LOCK"
  flock 8
    local d id line rows
    rows=""
    for d in "$OVER_ROOT"/*/; do
      [ -d "$d" ] || continue
      id="$(basename "$d")"
      overlay_pid_alive "$OVER_ROOT/$id" || continue
      rows="$rows$(cat "$d/slot" 2>/dev/null || echo 0) $id
"
    done
    # sort by current slot (numeric), then assign 0..N in that order
    local next=0
    while IFS=' ' read -r _oldslot rid; do
      [ -z "$rid" ] && continue
      printf '%s\n' "$next" > "$OVER_ROOT/$rid/slot" 2>/dev/null || true
      next=$((next+1))
    done <<EOF
$(printf '%s' "$rows" | sort -n)
EOF
  flock -u 8
}

cmd_start() {
  preflight || return 1
  local title="${1:-$OVERLAY_ID}"

  _reap                                      # clear any self-closed instances first
  mkdir -p "$INST" 2>/dev/null || true

  if overlay_is_running; then
    # already up — refresh title/state and return
    touch "$FLAG"; printf '%s\n' "$title" > "$TITLEF"
    echo "bureau overlay[$OVERLAY_ID]: already running (pid $(cat "$PIDF"))"
    return 0
  fi

  # Fresh launch: clear any stale pid from a prior crashed run so we don't look
  # "mid-launch" forever, then reserve a slot and spawn — all under one lock so a
  # concurrent start from another session can't grab the same slot before our
  # pid is written.
  rm -f "$PIDF" 2>/dev/null || true
  touch "$FLAG"
  : > "$FEED"
  printf 'working\n' > "$STATUS"
  printf 'shown\n' > "$VIS"
  printf '%s\n' "$title" > "$TITLEF"

  # Auto-fade delays (ms; 0 disables). DoneMs: after status hits 'done'. IdleMs:
  # safety net if nothing is written at all (a session that ended without setting
  # 'done') — defaults to 5 minutes.
  local done_ms="${BUREAU_OVERLAY_DONE_MS:-12000}"
  local idle_ms="${BUREAU_OVERLAY_IDLE_MS:-300000}"
  local wFeed wStatus wFlag wVis wSlot wTitle wHud
  wFeed="$(wslpath -w "$FEED")"; wStatus="$(wslpath -w "$STATUS")"
  wFlag="$(wslpath -w "$FLAG")"; wVis="$(wslpath -w "$VIS")"
  wSlot="$(wslpath -w "$SLOTF")"; wTitle="$(wslpath -w "$TITLEF")"
  wHud="$(wslpath -w "$HUD")"

  local slot pid
  exec 8>"$SLOTS_LOCK"
  flock 8
    slot="$(_pick_slot "$(_taken_slots | tr '\n' ' ')")"
    printf '%s\n' "$slot" > "$SLOTF"
    "$PS" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden \
      -File "$wHud" -Feed "$wFeed" -Status "$wStatus" -Flag "$wFlag" -Vis "$wVis" \
      -DoneMs "$done_ms" -IdleMs "$idle_ms" -SlotFile "$wSlot" -TitleFile "$wTitle" \
      >/dev/null 2>&1 &
    pid=$!
    echo "$pid" > "$PIDF"       # written before releasing the lock
  flock -u 8
  disown 2>/dev/null || true
  echo "bureau overlay[$OVERLAY_ID]: started (pid $pid, slot $slot) — \"$title\""
  return 0
}

cmd_stop() {
  rm -f "$FLAG" 2>/dev/null || true          # HUD self-closes on next tick
  if [ -f "$PIDF" ]; then
    local pid; pid="$(cat "$PIDF" 2>/dev/null)"
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
  fi
  rm -rf "$INST" 2>/dev/null || true         # drop only THIS instance
  _reap                                      # clear any self-closed instances too
  _repack                                    # close the gap: survivors slide up
  echo "bureau overlay[$OVERLAY_ID]: stopped"
  return 0
}

cmd_status() {
  if overlay_is_running; then echo "running (pid $(cat "$PIDF"), slot $(cat "$SLOTF" 2>/dev/null))"; else echo "not running"; fi
}

cmd_hide() { printf 'hidden\n' > "$VIS" 2>/dev/null || true; echo "bureau overlay[$OVERLAY_ID]: hiding"; }
cmd_show() { printf 'shown\n'  > "$VIS" 2>/dev/null || true; echo "bureau overlay[$OVERLAY_ID]: showing"; }

cmd_list() {
  _reap; _repack                             # tidy self-closed windows, close gaps
  local d id pid slot title alive
  local any=0
  for d in "$OVER_ROOT"/*/; do
    [ -d "$d" ] || continue
    any=1
    id="$(basename "$d")"
    pid="$(cat "$d/pid" 2>/dev/null || echo -)"
    slot="$(cat "$d/slot" 2>/dev/null || echo -)"
    title="$(cat "$d/title" 2>/dev/null || echo -)"
    if overlay_pid_alive "$OVER_ROOT/$id"; then alive="live"; else alive="dead"; fi
    printf '%-20s slot=%-2s pid=%-8s %-4s  %s\n' "$id" "$slot" "$pid" "$alive" "$title"
  done
  [ "$any" = "0" ] && echo "(no overlay instances)"
  return 0
}

cmd_stop_all() {
  local d id
  for d in "$OVER_ROOT"/*/; do
    [ -d "$d" ] || continue
    id="$(basename "$d")"
    rm -f "$d/armed" 2>/dev/null || true
    local pid; pid="$(cat "$d/pid" 2>/dev/null)"
    [ -n "$pid" ] && kill "$pid" 2>/dev/null || true
    rm -rf "$d" 2>/dev/null || true
    echo "stopped $id"
  done
}

case "${1:-}" in
  start)    shift; cmd_start "$@" ;;
  stop)     cmd_stop ;;
  status)   cmd_status ;;
  hide)     cmd_hide ;;
  show)     cmd_show ;;
  list)     cmd_list ;;
  stop-all) cmd_stop_all ;;
  *) echo "usage: overlay.sh {start [title]|stop|status|hide|show|list|stop-all}" >&2; exit 2 ;;
esac
