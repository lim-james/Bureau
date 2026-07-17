# /bureau-run

Stage 2 of the Bureau bootstrap. Run this after the direction contract has been approved.

## Prerequisites

- `.bureau/contracts/direction_v1.md` must exist in the current directory
- The direction contract must have been explicitly approved by the human

## Autonomy

The Bureau runs fully self-directed from this point. It does not stop to ask for input during the build. When the MVP is delivered, it notifies you and immediately continues into continuous improvement — it does not wait for your response. If you have feedback on the MVP, send it at any time and the Bureau will incorporate it into the next release cycle. Your feedback is never blocking.

---

### Voice narration (opt-in, ambient)

At the start, determine whether voice is armed: it is armed if `~/.bureau/voice.armed` already exists (carried over from `/bureau`, including its level) **or** if `$ARGUMENTS` contains the standalone keyword `jarvis` (case-insensitive) — in which case arm it, honouring an optional level word (`quiet`/`normal`/`verbose`/`briefing`) after `jarvis`: `echo <level> > ~/.bureau/voice.armed`, or `touch ~/.bureau/voice.armed` for the default.

If armed, emit spoken beats at the milestones below, each **tagged with a minimum level** via `-l`, and speak every **decision** through `decide.sh` (non-blocking, never awaited):
```
{{BUREAU_HOME}}/voice/narrate.sh -l <1|2|3> "<one concise status line, under ~15 words>"
{{BUREAU_HOME}}/voice/decide.sh "<the decision, its reason, and what it means>"
```
The script plays a beat only if it is audible at the active level, so **always emit every beat** and let the script decide what is heard.

**Levels:** `-l 1` quiet (build-start, MVP tagged, each release, blocked); `-l 2` normal (+ phase transitions, e.g. team X finished its scope); `-l 3` verbose (+ curated sub-steps, e.g. "tests green," "integrating team X's work," "committing"). Never narrate raw tool calls or per-file writes even at verbose — curated transitions only. Calm, declarative.

**Briefing — the "be the voice of the model" mode:** hears essentials + phase transitions + **the decisions themselves, spoken in full**, but skips the verbose mechanical sub-steps. Whenever the Bureau reaches a conclusion the human would otherwise have to read — an architecture call, a resolved trade-off, what shipped in a release and why, a chosen approach over its alternatives — speak it through `decide.sh` in 1–3 short sentences: the decision, the *because*, the *so-what*. `decide.sh` tags it `-l 4` and is **heard only in briefing** (a silent no-op otherwise), so always route decisions through it. Status still goes through `narrate.sh`. Example:
```
{{BUREAU_HOME}}/voice/decide.sh "Shipping v1.2 now: switched storage to SQLite because the JSON files were corrupting under concurrent writes — durability over simplicity."
```

Because this stage runs autonomously and continuously, **leave the voice armed** for the duration (do not disarm at MVP — continuous improvement should keep narrating its releases). Only disarm (`rm -f ~/.bureau/voice.armed`) if the human asks the Bureau to go quiet.

### Overlay HUD (opt-in, the visual sibling of voice)

The overlay is armed if `~/.bureau/overlay.armed` already exists (carried over from `/bureau`) **or** if `$ARGUMENTS` contains the standalone keyword `overlay`/`hud` — in which case launch it: `{{BUREAU_HOME}}/overlay/overlay.sh start`. If armed, push **one summary line per response** with `{{BUREAU_HOME}}/overlay/say.sh "<one-line distillation>"` (use `-k decision` for conclusions), and drive the status dot with `{{BUREAU_HOME}}/overlay/status.sh working|action|done|blocked` at meaningful moments (e.g. `action` when you need the human, `blocked` when stuck, `working` otherwise). All scripts self-gate and are safe no-ops when off. Like the voice, **leave the overlay running** for the duration of continuous improvement; only `overlay.sh stop` if the human asks. Overlay and voice are independent — emit to both when both are armed.

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
