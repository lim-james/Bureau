# /bureau-run

Stage 2 of the Bureau bootstrap. Run this after the direction contract has been approved.

## Prerequisites

- `.bureau/contracts/direction_v1.md` must exist in the current directory
- The direction contract must have been explicitly approved by the human

## Autonomy

The Bureau runs fully self-directed from this point. It does not stop to ask for input during the build. When the MVP is delivered, it notifies you and immediately continues into continuous improvement — it does not wait for your response. If you have feedback on the MVP, send it at any time and the Bureau will incorporate it into the next release cycle. Your feedback is never blocking.

---

### Voice narration (opt-in, ambient)

At the start, determine whether voice is armed: it is armed if `~/.bureau/voice.armed` already exists (carried over from `/bureau`) **or** if `$ARGUMENTS` contains the standalone keyword `jarvis` (case-insensitive) — in which case run `touch ~/.bureau/voice.armed` to arm it.

If armed, emit one short spoken beat at each intent-level milestone below via (non-blocking, never awaited):
```
{{BUREAU_HOME}}/voice/narrate.sh "<one concise line, under ~15 words>"
```
Narrate **intent and transitions only** — never individual tool calls, commits, or per-agent chatter (that noise defeats the point). Milestones for this stage: (a) teams formed and the build beginning; (b) a significant integration or milestone reached; (c) MVP complete and `v1.0.0` tagged; (d) each continuous-improvement release; (e) genuinely blocked, with the reason. Calm, declarative, sparse — a few beats, not a play-by-play. The script self-gates and is async, so it is a safe no-op when unarmed.

Because this stage runs autonomously and continuously, **leave the voice armed** for the duration (do not disarm at MVP — continuous improvement should keep narrating its releases). Only disarm (`rm -f ~/.bureau/voice.armed`) if the human asks the Bureau to go quiet.

---

Execute the following now:

1. Read the Bureau constitution from `.bureau/constitution/` — all files are constitutional law
2. Read the approved direction contract from `.bureau/contracts/direction_v1.md`
3. Read any existing records from `.bureau/records/` to understand who is already employed

4. Determine the team structure needed to deliver the MVP. For each team define:
   - A descriptive name
   - A clear scope
   - 2–9 employees with first and last names, roles, and first day
   Write all records to `.bureau/records/teams/`

5. Appoint partners. Record to `.bureau/records/partners.md`

6. Initialise a git repository if one does not exist. Set up an appropriate `.gitignore`.

7. **Spawn one Agent per team simultaneously using the Agent tool.** All team agents run in parallel. Do not run them sequentially. Each agent receives:
   - The direction contract
   - Its team name, scope, and employee roster
   - The instruction to commit frequently with format `[team-name] description`
   - The instruction to coordinate with other teams by reading their output files, not by waiting for them
   - Full autonomy — no permission requests, no stopping for clarification

8. The orchestrating agent monitors team progress and coordinates handoffs — e.g. infrastructure must be ready before build teams can compile; testing team integrates continuously as teams commit.

9. When all teams signal MVP complete:
   - Run the full test suite
   - Tag as v1.0.0 with `git tag v1.0.0`
   - Write `.bureau/releases/v1.0.0.md`
   - Notify the user: what was built, what's in v1.0.0, and that continuous improvement has begun
   - **Immediately** proceed without waiting for a response

10. Continuous improvement: spawn agents per role (researchers, devs, critics, testers) on a daily cron cadence. Each cycle that produces meaningful change is released as a new semver version.

11. User feedback at any time is high-priority input to the next cycle. Never block on it.

The Bureau moves in communion. Make decisions, ship, improve. Do not stop unless you are genuinely blocked on something only the user can resolve — and even then, describe the blocker clearly and continue with everything else you can.
