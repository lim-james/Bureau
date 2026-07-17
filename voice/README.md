# Bureau Voice — ambient narration ("JARVIS mode")

An opt-in voice layer that speaks intent-level updates into your headset while
the Bureau works, so you can keep your eyes on other things. It is **off by
default** and armed per-run by the keyword `jarvis`.

## How it works

```
orchestrator ─▶ narrate.sh ─▶ speak.sh ─▶ ElevenLabs TTS ─▶ Windows playback ─▶ headset
     │            │  (gate + queue)   │  (synth, verify TLS)
     │            │                   └─ SAPI fallback if API/network fails
  decide.sh ──────┘  (a decision beat — tags -l 4, briefing-only)
                   └─ silent no-op unless armed
```

- **narrate.sh** — the front door. Gates on the armed flag, serialises lines
  (flock) so beats never overlap, returns instantly (async) so the Bureau never
  blocks to talk.
- **decide.sh** — the seam for **decision beats**. A thin wrapper that tags a
  line `-l 4` and hands it to `narrate.sh`. Where `narrate.sh` speaks *status*
  ("a decision was made"), `decide.sh` speaks *substance* (the decision, its
  reason, its consequence). Heard **only in briefing mode**; a silent no-op
  otherwise, so the orchestrator can call it freely.
- **speak.sh** — synthesises one line via ElevenLabs (Jessica voice by default) and plays it
  through Windows' .NET `MediaPlayer` (native mp3, straight to the default
  Windows output = your headset). Verifies TLS against the corporate CA. Falls
  back to Windows SAPI if the API or network is unavailable — degrades, never
  goes unexpectedly silent, never crashes the caller.

## Turning it on

Add the word `jarvis` anywhere in your `/bureau` prompt:

```
/bureau jarvis, improve the export pipeline latency
```

Narration arms for that run and (via the carried-over flag) through the
`/bureau-run` build and continuous improvement. Without the keyword, the Bureau
is silent exactly as before.

## Verbosity — how much it says

Four levels. Add the level word right after `jarvis` to set it for one run:

```
/bureau jarvis quiet    <task>    # ~3 beats: started, done, blocked
/bureau jarvis normal   <task>    # ~5 beats: + each phase transition
/bureau jarvis verbose  <task>    # ~10-15 beats: + curated sub-steps
/bureau jarvis briefing <task>    # the decisions themselves, spoken in full
/bureau jarvis          <task>    # uses your persistent default (below)
```

Even `verbose` narrates *curated transitions* ("researcher three of six
reporting", "citations validated", "committing") — never a per-tool-call or
per-file readout, which would be exhausting in-ear.

### Briefing — be the voice of the model

`quiet`/`normal`/`verbose` form a ladder of *how much status* you hear; they all
tell you a decision **happened** and leave you to go read what it was. **Briefing**
is a different mode: it speaks the **decisions themselves** — the conclusion, the
reason, and what it means — so you can keep working on something else and *listen*
instead of reading.

```
verbose : "The founding panel has reached a direction."          ← you go read it
briefing: "Direction set: a read-only CLI first, because it       ← you already know
           covers the need and ships in days; the file-watcher
           becomes a fast-follow."
```

Briefing hears the essentials (level 1) and phase transitions (level 2) **plus**
full decision beats — but deliberately **drops** the verbose mechanical sub-steps
(level 3), which are noise to someone working alongside. Decision beats are spoken
via `decide.sh` and are heard **only** in briefing; in every other mode they are
silent, so the Bureau always emits them and the mode decides what you hear.

**Persistent default** — set the level used when you don't name one, in
`~/.bureau/voice.env`:

```
BUREAU_VOICE_LEVEL=normal     # quiet | normal | verbose | briefing
```

Resolution order for the active level: explicit `BUREAU_VOICE_LEVEL` env →
the level you typed after `jarvis` → the `voice.env` default → quiet.

Each beat is tagged with a level (`narrate.sh -l 1|2|3 "…"`, or `decide.sh` for
`-l 4`); the script speaks it only if it is audible at the active level. Levels
1–3 are a ladder (verbose hears 1–3). Briefing (4) is a distinct mode, not a
louder verbose: it hears levels 1, 2 and 4 (decisions) but **not** 3 (verbose
mechanics). Decision beats (level 4) are heard only in briefing. The orchestrator
always emits every beat — the mode decides what you actually hear.

## Manual control / testing

```
BUREAU_VOICE=1 voice/speak.sh "direct line, bypasses the gate"     # force-speak
BUREAU_VOICE=1 voice/narrate.sh "queued line"                      # force via queue
BUREAU_VOICE=1 BUREAU_VOICE_LEVEL=briefing voice/decide.sh "The decision, and why."  # a decision beat
echo briefing > ~/.bureau/voice.armed   # arm in briefing mode
touch ~/.bureau/voice.armed     # arm manually (uses default level)
rm -f ~/.bureau/voice.armed     # disarm
tail -f ~/.bureau/voice.log     # see what was spoken, with timestamps
```

## Config — `~/.bureau/voice.env` (gitignored, never committed)

```
ELEVENLABS_API_KEY=...            # required for the good voice
BUREAU_VOICE_ID=cgSgspJ2msm6clMCkdW9   # default: Jessica (playful, bright, warm)
BUREAU_VOICE_MODEL=eleven_turbo_v2_5   # low-latency streaming model
BUREAU_VOICE_CA=~/.bureau/corp-chain.pem   # corporate TLS CA chain
```

To change voice, set `BUREAU_VOICE_ID` to any voice_id from your ElevenLabs
account (`GET /v1/voices`).

## Notes / known constraints

- **Corporate network:** this environment intercepts TLS, so requests verify
  against `~/.bureau/corp-chain.pem` (captured from the live chain). If you move
  networks and synthesis fails with a cert error, re-capture it:
  `openssl s_client -showcerts -connect api.elevenlabs.io:443 </dev/null 2>/dev/null | awk '/BEGIN CERTIFICATE/,/END CERTIFICATE/' > ~/.bureau/corp-chain.pem`
- **First call latency:** ~1s PowerShell warm-up + ~0.5s synthesis. Subsequent
  lines are quick.
- **Voice input** (you talking back) is intentionally out of scope for now.
- Secrets and runtime state live under `~/.bureau/` (outside the repo) and are
  never committed.
