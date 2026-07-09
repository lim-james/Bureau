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
