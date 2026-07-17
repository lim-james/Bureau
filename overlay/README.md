# Bureau Overlay — glass teleprompter HUD

An opt-in, always-on-top **view** over a running Bureau: a rounded, semi-glass
window pinned to the top-right corner that types out a one-line summary of each
response and shows a status dot (working / action-needed / done / blocked). It is
the *visual sibling* of the [voice](../voice/README.md) module — same WSL→Windows
bridge, same opt-in, silent-by-default philosophy.

It is a **pure view**: non-interactive and click-through (it never steals your
mouse), reads two files written by the Bureau, and never writes back. Use it to
keep half an eye on a background run while you work on something else.

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

## Requirements & degradation

**WSL-on-Windows only** — it renders by invoking Windows `powershell.exe` (WPF)
via `/mnt/c`. It needs `wslpath` and `powershell.exe`. On native Linux/macOS the
overlay is unsupported and simply does nothing (the Bureau runs fine without it).
No installs — WPF ships with Windows.

## Files (under `~/.bureau/`, outside any repo)

```
overlay.armed    presence = armed; the HUD watches this and self-closes when gone
overlay.feed     the summary lines (kind<TAB>text), trimmed to the last 40
overlay.status   one token: working | action | done | blocked
overlay.vis      one token: shown | hidden  (drives the slide in/out)
overlay.pid      the launched powershell.exe pid (best-effort cleanup)
```
