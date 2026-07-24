# Bureau Overlay — glass teleprompter HUD

An opt-in, always-on-top **view** over a running Bureau: a rounded, semi-glass
window pinned to the top-right corner that types out a one-line summary of each
response and shows a status dot (working / action-needed / done / blocked). It is
the *visual sibling* of the [voice](../voice/README.md) module — same WSL→Windows
bridge, same opt-in, silent-by-default philosophy.

It is a **pure view**: non-interactive and click-through (it never steals your
mouse), reads files written by the Bureau, and never writes back. Use it to
keep half an eye on a background run while you work on something else.

## Multi-session

Several Bureau sessions can run at once, each with its own HUD. Every overlay is
an **instance** keyed by `BUREAU_OVERLAY_ID` (a short, stable id derived from the
task). Each instance gets its own namespaced files under
`~/.bureau/overlay/<id>/` and an auto-assigned **stack slot**, so the windows
tile down the right edge without colliding — no shared feed, no shared pid, no
overwriting. A window shows a **descriptive title** (set at `start`) so you can
tell sessions apart. Slots are reclaimed when an instance stops or dies.

```
export BUREAU_OVERLAY_ID=export-latency
overlay/overlay.sh start "Export pipeline — latency work"
overlay/overlay.sh list        # all instances: id, slot, pid, title
overlay/overlay.sh stop-all    # stop every instance
```
If you never set `BUREAU_OVERLAY_ID`, everything falls back to a single instance
named `default` — fine for one session.

## How it works

```
orchestrator ─▶ say.sh    ─▶ overlay.feed  ─┐
                status.sh ─▶ overlay.status ┼─▶ hud.ps1 (WPF glass window)
                overlay.sh (start/stop/hide/show) ─▶ launches + controls it
```

- **say.sh** — append a one-line summary of the current response to the feed.
  Lines have a *kind* that sets their accent colour: `summary` (bright),
  `decision` (blue), `status` (dim), `action` (amber).
- **status.sh** — set the persistent status indicator: `working` (calm blue),
  `action` (amber, pulsing), `done` (green), `blocked` (red, pulsing).
- **overlay.sh** — lifecycle: `start` arms + launches the window, `stop` closes
  it (with an exit animation) and cleans up, `hide`/`show` slide it out/in
  without quitting, `status` reports whether it's running.
- **hud.ps1** — the window itself. Borderless, topmost, click-through, rounded,
  near-black glass. Shows the last **3** lines with a teleprompter fade, types
  the newest out character-by-character, and fades + slides in/out with cubic
  easing. Self-closes the instant the armed flag disappears.

### On finish — auto-fade

When status is set to `done`, the HUD holds green for a short delay (~12s), then
fades + slides out and closes on its own — so a finished run tidies itself away
without a manual `stop`. The countdown is **cancelled** if the status changes
back (e.g. the next continuous-improvement cycle sets `working`), so it never
vanishes mid-run. Tune or disable via `BUREAU_OVERLAY_DONE_MS` (milliseconds;
`0` disables auto-fade — the window then stays until `overlay.sh stop`).

**Idle safety net.** The `done` fade only fires if something actually sets
`done`. If a session ends, crashes, or just goes quiet **without** setting
`done`, an idle timeout fades the window anyway: if nothing is written to the
instance (no new feed line, no status change) for `BUREAU_OVERLAY_IDLE_MS`
(default **5 minutes**), it fades out. Any new activity resets the clock, so a
still-working run never disappears. Set `BUREAU_OVERLAY_IDLE_MS=0` to disable.

## Turning it on

Like the voice, it arms per-run via a keyword in your `/bureau` prompt
(`overlay`, or the combined `hud`). Or drive it manually:

```
overlay/overlay.sh start        # arm + show the window
overlay/say.sh "A one-line summary of what just happened."
overlay/say.sh -k decision "A decision, in the blue accent."
overlay/status.sh action        # flip the dot to ACTION NEEDED
overlay/overlay.sh hide         # slide it out (still running)
overlay/overlay.sh show         # slide it back in
overlay/overlay.sh stop         # animate out + close + clean up
```

## What it shows

The overlay summarises — it is **not** a transcript. Each response the Bureau
produces becomes one glanceable line (plus a status). There is no API and no
live prompt feed: the character-by-character reveal is a local effect, so the
only input is the summary line the orchestrator chooses to push.

## Activity mode — the mechanical ticker

The summary feed is a *narrative* view. **Activity mode** adds the complementary
*mechanical* view: a single ticker row pinned below the summaries that shows the
actual work as it happens — `✎ editing hud.ps1`, `❯ running npm test`,
`⌕ searching …`, `◆ delegating …` — with a live braille spinner while a burst is
in flight, settling and hiding itself when the work goes quiet. A failed bash
command flashes the row red.

It is driven **automatically** by a Claude Code **tool-call hook**
(`activity-hook.sh`, registered as `PreToolUse`/`PostToolUse` in the project's
`.claude/settings.json`), so nothing has to be narrated by hand — every edit,
read, command, search, and sub-agent is captured. The hook is a fast **no-op**
unless activity mode is armed for the current project dir, so leaving it
registered costs nothing.

```
overlay/overlay.sh activity on     # arm the ticker (binds to $CLAUDE_PROJECT_DIR / cwd)
overlay/overlay.sh activity off    # disarm it
```

Arm it per-run via the `activity` (or `verbose`) keyword in a `/bureau` prompt,
alongside `overlay`/`hud`. The hook has no `BUREAU_OVERLAY_ID` of its own (it
fires from the harness, not the orchestrator), so it discovers the target window
by matching its recorded project dir (`act.cwd`) — the most recently armed
instance for that dir wins.

## Requirements & degradation

**WSL-on-Windows only** — it renders by invoking Windows `powershell.exe` (WPF)
via `/mnt/c`. It needs `wslpath` and `powershell.exe`. On native Linux/macOS the
overlay is unsupported and simply does nothing (the Bureau runs fine without it).
No installs — WPF ships with Windows.

## Files (under `~/.bureau/overlay/`, outside any repo)

Per-instance, namespaced by `BUREAU_OVERLAY_ID` (`<id>` below):

```
overlay/slots.lock       lock for atomic stack-slot assignment across instances
overlay/<id>/armed       presence = armed; the HUD watches this and self-closes when gone
overlay/<id>/feed        the summary lines (kind<TAB>text), trimmed to the last 40
overlay/<id>/status      one token: working | action | done | blocked
                         (holding 'done' ~12s auto-fades the window; see On finish above)
overlay/<id>/vis         one token: shown | hidden  (drives the slide in/out)
overlay/<id>/pid         the launched powershell.exe pid (best-effort cleanup)
overlay/<id>/title       the descriptive window title
overlay/<id>/slot        this instance's stack position (0 = top)
overlay/<id>/act.on      presence = activity ticker armed for this instance
overlay/<id>/act.cwd     the project dir the tool-call hook routes activity from
overlay/<id>/act.line    the current ticker line (kind<TAB>text), updated in place
```
