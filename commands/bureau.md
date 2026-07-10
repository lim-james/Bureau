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

- **If present:** the human wants ambient voice narration for this run. Check whether an optional **level word** follows `jarvis` — one of `quiet`, `normal`, or `verbose`:
  - Arm at that level by writing it to the flag: e.g. `echo verbose > ~/.bureau/voice.armed` (or `quiet`/`normal`). If no level word is given, arm with the default: `touch ~/.bureau/voice.armed` (the script then uses the persistent default in `~/.bureau/voice.env`, or quiet).
  - Strip `jarvis` **and** the level word from the problem statement before using it (they are instructions to you, not part of the task).
  - Then emit spoken beats at the milestones below, each **tagged with a minimum level** via `-l`:
    ```
    {{BUREAU_HOME}}/voice/narrate.sh -l <1|2|3> "<one concise line>"
    ```
    The script plays a beat only if the active level is at least its tag, so you should **always emit every beat** — the script decides what is heard. Do not self-censor by level.
- **If absent:** do nothing voice-related. Stay silent. Never arm the voice on your own.

**Verbosity levels (what each tag means):**
- **`-l 1` (quiet — the default):** the essentials only — started, done/contract-ready, blocked. ~3 beats for a whole run.
- **`-l 2` (normal):** the above **plus** each phase transition. ~5 beats.
- **`-l 3` (verbose):** the above **plus** curated sub-steps — e.g. "researcher three of six reporting," "findings synthesised," "citations validated," "committing now." ~10–15 beats. Still curated meaningful transitions — **never** a per-tool-call or per-file readout, which would be unbearable in-ear.

**Narration discipline (this is what keeps it JARVIS, not a screen-reader):**
- Always narrate **intent and transitions**, never raw tool calls. Verbose adds *more transitions*, not raw mechanics.
- One line per beat, ideally under ~15 words, calm and declarative — a status update from a trusted operator.
- Tag beats so quiet still makes sense on its own: milestone beats get `-l 1` (convened / contract-ready) or `-l 2` (phase transitions); sub-step beats get `-l 3`.
- The script self-gates on the armed flag and level, and is fully async — calling it is always a safe no-op if unarmed or above level. Do not `await` or block on it.
- When the run finishes (contract surfaced for approval), disarm with `rm -f ~/.bureau/voice.armed` so narration does not leak into a later un-armed run.

Example beats, after arming:
```
{{BUREAU_HOME}}/voice/narrate.sh -l 1 "Convening the founding panel — three specialists."
{{BUREAU_HOME}}/voice/narrate.sh -l 3 "Strategist and researcher reporting; critic still working."
{{BUREAU_HOME}}/voice/narrate.sh -l 1 "Direction contract ready for your review."
```

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
