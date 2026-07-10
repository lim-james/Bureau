# Bureau Voice — ambient narration ("JARVIS mode")

An opt-in voice layer that speaks intent-level updates into your headset while
the Bureau works, so you can keep your eyes on other things. It is **off by
default** and armed per-run by the keyword `jarvis`.

## How it works

```
orchestrator ──▶ narrate.sh ──▶ speak.sh ──▶ ElevenLabs TTS ──▶ Windows playback ──▶ headset
                   │  (gate + queue)   │  (synth, verify TLS)
                   │                   └─ SAPI fallback if API/network fails
                   └─ silent no-op unless armed
```

- **narrate.sh** — the front door. Gates on the armed flag, serialises lines
  (flock) so beats never overlap, returns instantly (async) so the Bureau never
  blocks to talk.
- **speak.sh** — synthesises one line via ElevenLabs (Lily voice) and plays it
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
`/bureau-run` build and continuous improvement. It narrates ~5 milestones per
run — convened, contract ready, building, milestone/release, done/blocked — not
a step-by-step readout.

Without the keyword, the Bureau is silent exactly as before.

## Manual control / testing

```
BUREAU_VOICE=1 voice/speak.sh "direct line, bypasses the gate"     # force-speak
BUREAU_VOICE=1 voice/narrate.sh "queued line"                      # force via queue
touch ~/.bureau/voice.armed     # arm manually
rm -f ~/.bureau/voice.armed     # disarm
tail -f ~/.bureau/voice.log     # see what was spoken, with timestamps
```

## Config — `~/.bureau/voice.env` (gitignored, never committed)

```
ELEVENLABS_API_KEY=...            # required for the good voice
BUREAU_VOICE_ID=pFZP5JQG7iQjIQuC4Bku   # default: Lily (British, velvety)
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
