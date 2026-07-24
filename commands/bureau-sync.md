# /bureau-sync

Check an existing Bureau for updates to the constitution and account for them.

The canonical constitution lives at `{{BUREAU_HOME}}/docs/`. When a Bureau is founded, those docs are copied into the project's `.bureau/constitution/`. Over time the canonical constitution evolves — new laws, new roles, new mechanisms. This command brings an existing Bureau up to date and forces its partners to formally account for what changed.

## Prerequisites

- The current directory must contain a `.bureau/` — i.e. this is an existing Bureau
- `.bureau/constitution/` must exist (the Bureau's copy of the constitution at founding)

## Usage

```
/bureau-sync
```

## What this command does

1. Confirms this is an existing Bureau (a `.bureau/` directory is present). If not, stop and tell the user to run `/bureau` first.

2. Compare the canonical constitution at `{{BUREAU_HOME}}/docs/` against the Bureau's copy at `.bureau/constitution/`:
   - New files in canonical that are absent from the Bureau's copy
   - Files that differ (changed law)
   - Files removed from canonical
   Use a file-by-file diff. Surface a clear summary of every change to the user before applying anything.

3. If there are no differences, report that the Bureau is already up to date and stop.

4. If there are differences, update `.bureau/constitution/` to match the canonical constitution exactly — add new files, overwrite changed files, remove deleted ones. Record the sync to `.bureau/records/constitution_sync.md` with the date and a summary of what changed.

5. **Audit the Bureau's actual state against the now-updated constitution.** This is the core purpose of the command: updating the text is not enough — the Bureau must *adhere* to it. Inspect the real state of the Bureau and find every point of non-compliance. For each constitutional law, check the Bureau lives up to it. For example:
   - Directories the constitution requires that don't exist yet (e.g. `.bureau/feedback/` for [External Feedback]({{BUREAU_HOME}}/docs/feedback.md), `.bureau/backlog/` for the [Backlog]({{BUREAU_HOME}}/docs/backlog.md))
   - A backlog that is missing or does not reflect outstanding obligations — every open feedback item, accepted-and-undone finding, and deferred answer that already exists in the Bureau's records must have a corresponding backlog item (see [Backlog]({{BUREAU_HOME}}/docs/backlog.md))
   - Records the constitution requires that are missing or incomplete (e.g. partner records, team first/last days, employee names)
   - Mechanisms the constitution mandates that aren't in place (e.g. the daily improvement cron, version tracking in `.bureau/releases/`, end-of-phase consultancy audits)
   - **The Automatic Routing hook** ([routing.md]({{BUREAU_HOME}}/docs/routing.md)): is a `UserPromptSubmit` hook registered in `.claude/settings.json` that runs `{{BUREAU_HOME}}/hooks/bureau-route-hook.sh`? A Bureau whose settings predate v2.3.0 will lack it, which means prompts silently bypass the pipeline — the exact failure routing.md exists to fix. This is a mandated mechanism; its absence is an adherence gap.
   - Roles or employment types now defined that the Bureau's records don't reflect
   - Any team, scope, or structure that now violates a changed law (e.g. a team exceeding the size ceiling)
   Produce an explicit **adherence report** — every gap between the constitution and the Bureau's reality — and record it to `.bureau/records/constitution_sync.md`.

6. **Remediate every gap so the Bureau adheres.** Mechanical, unambiguous compliance is applied directly — create required directories, backfill missing records, stand up mandated scaffolding. Do not wait for a meeting to create a folder the constitution plainly requires. This includes creating `.bureau/backlog/` and backfilling it from existing records: scan `.bureau/feedback/` and any recorded findings, and create a backlog item for every outstanding obligation (open feedback acted upon, accepted-but-undone findings, deferred answers) that does not already have one. It also includes **registering the Automatic Routing hook** if missing: add a `UserPromptSubmit` hook to `.claude/settings.json` pointing at `{{BUREAU_HOME}}/hooks/bureau-route-hook.sh` (merge into the existing `hooks` object; do not clobber the overlay Pre/PostToolUse hooks). Validate the result is still valid JSON.

7. **Convene a partner meeting for the changes that require judgement.** Spawn the partners (from `.bureau/records/partners.md`) and have them deliberate, per [Partners]({{BUREAU_HOME}}/docs/partners.md) and [External Feedback]({{BUREAU_HOME}}/docs/feedback.md), on any gap that isn't a mechanical fix — anything affecting phase plans, structure, intent, or that needs bounded work to resolve. For each, decide:
   - **Carry on** — the Bureau already complies, or subsequent phases already bring it into compliance
   - **Replan** — the change requires reshaping current phase work
   - **Escalate to founding** — the change touches intent; reconvene the founding team to revise the direction contract
   - **Commission a consultant** — a bounded task is needed to comply; stand up the consultancy team(s), scoped to compliance, dissolved once done
   Partner decisions require consensus. A split means no decision — partners reconvene. Record every disposition to `.bureau/records/constitution_sync.md`.

8. Apply the partners' decisions, then verify: re-check the adherence report and confirm every gap is either resolved or has a recorded, in-progress disposition. The command's success condition is that the Bureau adheres to the updated constitution — not merely that the text was copied.

9. Report to the user: what changed in the constitution, the adherence gaps found, what was remediated directly, how partners dispositioned the rest, and what work is in motion. Then continue autonomously — this command is not blocking.

## Notes

- This command never silently rewrites the Bureau's behaviour. Constitutional changes are always surfaced, and every adherence gap is either remediated on the record or dispositioned by partners on the record.
- The constitution is law. Once synced, the updated `.bureau/constitution/` is authoritative for this Bureau — and the Bureau's real state must match it. Updating the text without enforcing adherence is an incomplete sync.
