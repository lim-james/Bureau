# The Bureau

A multi-agent framework for [Claude Code](https://claude.com/claude-code) that tackles a task by standing up an *organisation* — employees with scoped roles, grouped into flat teams that move in communion toward the goal. Specialisation minimises hallucination; no one operates alone; nothing ships without a counterpart checking it.

The Bureau is governed by a **constitution** (the `docs/` directory) — a set of laws that every agent reads and adheres to. You give it a problem; it founds a team, agrees a direction contract with you, builds to an MVP, then keeps improving itself.

## How it works

The Bureau runs in two phases, with the MVP as the hinge between them:

1. **Delivery** — a founding team turns your task into a direction contract (you approve it), then operational teams build to the MVP and ship it as `v1.0.0`.
2. **Continuous improvement** — a daily cycle where every role pushes the project forward: researchers scan outward, developers refactor, critics audit, testers close gaps, partners steward structure. Every meaningful change is a new semver release.

Supporting mechanisms, all defined in the constitution:

- **External feedback** — your feedback is never blocking; partners deliberate how to account for it (carry on, replan, escalate, or commission a consultant).
- **Consultants** — temporary hires for a bounded task or audit; at the end of every phase, consultancy teams rigorously check the whole project, then leave.
- **Backlog** — a single ledger of outstanding work at `.bureau/backlog/`, closed by commit trailers (`Closes: backlog-…`).
- **Findings discipline** — every finding is recorded and formally answered; every external claim must be cited so it can be cross-checked.

Read [`docs/overview.md`](docs/overview.md) for the full picture.

## Quickstart

```bash
# 1. Clone this repo somewhere central and keep it — it is the canonical constitution.
git clone git@github.com:lim-james/Bureau.git ~/bureau

# 2. Install the slash commands into ~/.claude/commands/ (points them at this clone).
cd ~/bureau && ./install.sh

# 3. In ANY project directory, found a bureau:
cd ~/my-project
```
Then, inside Claude Code:
```
/bureau Build a CLI tool that monitors file changes in a directory and logs them with timestamps
```

The founding team convenes and shows you a **direction contract**. Review it, then approve:

```
/bureau-run
```

The Bureau builds to the MVP and continues autonomously into continuous improvement.

## Commands

| Command | What it does |
|---------|--------------|
| `/bureau <problem>` | Stage 1 — founds the bureau, produces the direction contract, stops for your approval. |
| `/bureau-run` | Stage 2 — forms operational teams and builds to the MVP (run after approving the contract). |
| `/bureau-sync` | Updates an existing bureau to the latest constitution and enforces adherence. |

## Keeping a bureau up to date

The constitution evolves. To pull updates into a project you founded earlier:

```bash
cd ~/bureau && git pull && ./install.sh   # refresh the canonical constitution + commands
cd ~/my-project                            # then, in Claude Code:
```
```
/bureau-sync
```

`/bureau-sync` diffs your project's constitution against this clone, updates it, then audits the bureau's actual state and brings it into compliance — creating any required scaffolding, backfilling records and the backlog, and convening partners for anything needing judgement.

## Voice narration (optional)

The Bureau can speak ambient, intent-level status updates into your headset while
it works — armed per-run by adding the word `jarvis` to a `/bureau` prompt, and
silent otherwise. It is entirely optional: **skip this and the Bureau works
exactly the same, just without audio.**

There is also a **briefing** mode (`jarvis briefing`) where the Bureau becomes
the *voice of the model*: instead of telling you a decision was made and leaving
you to go read it, it speaks the decision itself — the conclusion, the reason,
and what it means — so you can listen while working on something else.

**Requirements:** this feature is **WSL-on-Windows only** (it plays audio by
invoking Windows). It needs `curl`, `python3`, `wslpath`, and Windows
`powershell.exe` reachable via `/mnt/c`. On native Linux/macOS it is unsupported
and stays silent — no error, the Bureau just runs without it.

**Setup:**
```bash
mkdir -p ~/.bureau
cp voice/voice.env.example ~/.bureau/voice.env
chmod 600 ~/.bureau/voice.env         # holds your API key
# then edit ~/.bureau/voice.env and paste an ElevenLabs API key
```
Without a key it falls back to the robotic Windows SAPI voice. On a corporate
network that intercepts TLS, see the `BUREAU_VOICE_CA` note in the example file.

**Use it:**
```
/bureau jarvis <task>            # narrate at your default level
/bureau jarvis verbose <task>    # more detail (quiet | normal | verbose)
/bureau jarvis briefing <task>   # speak the decisions themselves, in full
```
Full details in [`voice/README.md`](voice/README.md).

## Repository layout

```
docs/            The constitution — one law per file (read by every agent)
commands/        Slash-command definitions (installed to ~/.claude/commands/)
voice/           Optional voice narration (WSL-only); see voice/README.md
install.sh       Installs commands, pointing them at this clone
bootstrap.md     The two-stage bootstrap process
```

A founded bureau keeps its runtime state in `.bureau/` inside the project — records, contracts, feedback, backlog, and releases. Voice secrets/config live in `~/.bureau/` (outside any repo) and are never committed.
