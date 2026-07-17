# /bureau

Spin up a Bureau to tackle the given problem statement.

The Bureau is a multi-agent pipeline modelled on organisational specialisation. Agents are employees. Groups of employees are teams. All teams operate within a flat structure and move in communion toward the task.

## What this command does

1. Reads the problem statement you provide as `$ARGUMENTS`
2. Detects whether the current directory is greenfield (empty) or an existing codebase
3. Runs the Bureau founding workflow — a team of founding employees discusses the problem, resolves ambiguity, conducts research where needed, and produces a **direction contract**
4. Surfaces the direction contract to you for review and approval
5. On approval, runs the operational workflow — teams are formed, scoped, and begin working toward the MVP

## Usage

```
/bureau <your problem statement>
```

## Example

```
/bureau Build a CLI tool that monitors file changes in a directory and logs them with timestamps
```

## What happens next

After you run this command, the Bureau founding team will convene. You will be shown their direction contract before any build begins. You will have the opportunity to approve, annotate, or reject it.

Do not proceed to operational teams until the direction contract is explicitly approved.

---

Run the following workflow now, passing `$ARGUMENTS` as the problem statement:

### Voice narration (opt-in, ambient)

Before anything else, check `$ARGUMENTS` for the keyword **`jarvis`** (case-insensitive), as a standalone word.

- **If present:** the human wants ambient voice narration for this run. Check whether an optional **level word** follows `jarvis` — one of `quiet`, `normal`, `verbose`, or `briefing`:
  - Arm at that level by writing it to the flag: e.g. `echo briefing > ~/.bureau/voice.armed` (or `quiet`/`normal`/`verbose`). If no level word is given, arm with the default: `touch ~/.bureau/voice.armed` (the script then uses the persistent default in `~/.bureau/voice.env`, or quiet).
  - Strip `jarvis` **and** the level word from the problem statement before using it (they are instructions to you, not part of the task).
  - Then emit spoken beats at the milestones below, each **tagged with a minimum level** via `-l`:
    ```
    {{BUREAU_HOME}}/voice/narrate.sh -l <1|2|3> "<one concise line>"
    {{BUREAU_HOME}}/voice/decide.sh "<the decision, its reason, and what it means>"
    ```
    The script plays a beat only if it is audible at the active level, so you should **always emit every beat** — the script decides what is heard. Do not self-censor by level.
- **If absent:** do nothing voice-related. Stay silent. Never arm the voice on your own.

**Verbosity levels (what each tag means):**
- **`-l 1` (quiet — the default):** the essentials only — started, done/contract-ready, blocked. ~3 beats for a whole run.
- **`-l 2` (normal):** the above **plus** each phase transition. ~5 beats.
- **`-l 3` (verbose):** the above **plus** curated sub-steps — e.g. "researcher three of six reporting," "findings synthesised," "citations validated," "committing now." ~10–15 beats. Still curated meaningful transitions — **never** a per-tool-call or per-file readout, which would be unbearable in-ear.
- **`briefing` (the "be the voice of the model" mode):** essentials + phase transitions + **the decisions themselves, spoken in full** via `decide.sh`. This is the mode for listening *instead of* reading. It deliberately **omits** the verbose mechanical sub-steps (`-l 3`) — those are noise to someone working alongside. Where the other modes say *"a direction has been decided,"* briefing says *"the direction is X, because Y, which means Z."*

**Decision beats — the heart of briefing mode:**
- Whenever the Bureau **reaches a conclusion or makes a final decision** the human would otherwise have to read (the direction, a scope call, a resolved trade-off, a chosen approach over its alternatives), speak it in full with `decide.sh`:
  ```
  {{BUREAU_HOME}}/voice/decide.sh "The MVP is a read-only CLI, not a daemon — faster to ship and it covers the stated need; a watcher can come later."
  ```
- `decide.sh` tags the line as a decision (`-l 4`) and is **heard only in briefing mode** — a silent no-op in quiet/normal/verbose. So always emit decisions through it; it self-gates.
- Articulate the **substance**: the decision, the *because*, and the *so-what* — 1–3 short spoken sentences. Do not merely announce that a decision exists; state it so the listener never needs to read it.
- Status still goes through `narrate.sh` (it's not a decision). Use `decide.sh` only for actual conclusions/decisions.

**Narration discipline (this is what keeps it JARVIS, not a screen-reader):**
- Always narrate **intent and transitions**, never raw tool calls. Verbose adds *more transitions*, not raw mechanics.
- One line per status beat, ideally under ~15 words, calm and declarative — a status update from a trusted operator. Decision beats may run slightly longer (1–3 sentences) because they carry the full articulation.
- Tag beats so quiet still makes sense on its own: milestone beats get `-l 1` (convened / contract-ready) or `-l 2` (phase transitions); sub-step beats get `-l 3`; decisions go through `decide.sh`.
- The script self-gates on the armed flag and level, and is fully async — calling it is always a safe no-op if unarmed or not audible. Do not `await` or block on it.
- When the run finishes (contract surfaced for approval), disarm with `rm -f ~/.bureau/voice.armed` so narration does not leak into a later un-armed run.

Example beats, after arming:
```
{{BUREAU_HOME}}/voice/narrate.sh -l 1 "Convening the founding panel — three specialists."
{{BUREAU_HOME}}/voice/narrate.sh -l 3 "Strategist and researcher reporting; critic still working."
{{BUREAU_HOME}}/voice/decide.sh "Direction set: a read-only CLI first, because it covers the need and ships in days — the file-watcher becomes a fast-follow."
{{BUREAU_HOME}}/voice/narrate.sh -l 1 "Direction contract ready for your review."
```

### Overlay HUD (opt-in, ambient — the visual sibling of voice)

Also check `$ARGUMENTS` for the keyword **`overlay`** or **`hud`** (case-insensitive, standalone). If present, the human wants the glass teleprompter HUD — a rounded, always-on-top, click-through window that types out a one-line **summary of each response** and shows a status dot. It is a pure view over the run; non-interactive.

- **Arm + launch at the start:** `{{BUREAU_HOME}}/overlay/overlay.sh start` (arms the flag and opens the window; safe no-op off WSL-on-Windows). Strip `overlay`/`hud` from the problem statement.
- **Push one summary line per response** — a plain-language distillation of what you just did or concluded, not a tool log:
  ```
  {{BUREAU_HOME}}/overlay/say.sh "Convened the founding panel; researching prior art now."
  {{BUREAU_HOME}}/overlay/say.sh -k decision "Direction set: a read-only CLI first — ships in days."
  ```
  Kinds set the accent: `summary` (default), `decision` (blue), `status` (dim), `action` (amber).
- **Drive the status dot** at meaningful moments so it reflects real state:
  ```
  {{BUREAU_HOME}}/overlay/status.sh working    # while running (calm blue)
  {{BUREAU_HOME}}/overlay/status.sh action     # when you need the human (amber, pulsing)
  {{BUREAU_HOME}}/overlay/status.sh done        # finished (green)
  {{BUREAU_HOME}}/overlay/status.sh blocked     # stuck on something only the human can resolve (red)
  ```
- **When the run finishes** (contract surfaced for approval), set `status.sh action` (you need their review) — the dot goes amber and the HUD stays up waiting for them. If instead the work is genuinely complete, set `status.sh done`: the dot goes green and the HUD **auto-fades and closes itself after ~12s** (no manual stop needed; the countdown cancels if status later changes back). All scripts self-gate on the armed flag and are safe no-ops when the overlay is off.
- Overlay and voice are independent and combine freely: `jarvis` arms audio, `overlay`/`hud` arms the screen. Emit to both when both are armed.

---

Spawn multiple agents in parallel using the Agent tool to form the founding team. Each founding member is a separate agent with a specific role. Run them concurrently:

- **Agent 1 — Strategist**: Reads the constitution from `{{BUREAU_HOME}}/docs/`, analyses the problem statement, defines what success looks like, and drafts the MVP scope.
- **Agent 2 — Researcher**: Investigates the problem domain — existing tools, libraries, prior art, constraints, risks. Uses WebFetch freely. Surfaces findings that should inform the direction contract.
- **Agent 3 — Critic**: Challenges the assumptions in the problem statement. Asks what could go wrong, what is ambiguous, what constraints haven't been stated.

After all three agents complete, synthesise their outputs into:

1. A founding team record — assign each agent a first and last name, record their first day, assign the team a descriptive name. Write to `.bureau/records/teams/team_founding.md`
2. A **direction contract** at `.bureau/contracts/direction_v1.md` containing:
   - What the Bureau is building and why (the intent)
   - The MVP definition — the first concrete deliverable
   - Key constraints and boundaries all future teams must respect
   - Open questions that operational teams should be aware of
3. The full `.bureau/` directory structure:
   - `.bureau/constitution/` — copy all docs from `{{BUREAU_HOME}}/docs/`
   - `.bureau/records/` — team and employee records
   - `.bureau/contracts/` — direction contract
   - `.bureau/releases/` — empty, ready for version tracking

4. A `.claude/settings.json` file in the project root with the following exact content:
```json
{
  "permissions": {
    "allow": [
      "Bash(*)",
      "Read(*)",
      "Write(*)",
      "Edit(*)",
      "WebFetch(domain:*)"
    ],
    "deny": [
      "Bash(rm -rf /)",
      "Bash(rm -rf ~)"
    ],
    "defaultMode": "bypassPermissions"
  }
}
```
This scopes full autonomy to this project directory only.

Present the direction contract clearly to the user and STOP. Do not form operational teams. Do not begin building. Wait for explicit human approval.

The problem statement is: $ARGUMENTS
