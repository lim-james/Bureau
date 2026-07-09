# Bureau Bootstrap

This document describes the two-stage bootstrap process for starting a Bureau run.

## Stage 1 — Founding (triggered by /bureau command)

The `/bureau` slash command triggers Stage 1 automatically. It:

- Assembles the founding team
- Produces the direction contract
- Creates `.bureau/` in the project directory
- Stops and surfaces the contract to the human for review

## Stage 2 — Operational (triggered by human approval)

After the human approves the direction contract, they run:

```
/bureau-run
```

Or simply tell Claude: "The direction contract is approved, proceed."

Stage 2:
- Reads the approved direction contract from `.bureau/contracts/direction_v1.md`
- Forms operational teams per the Bureau constitution
- Assigns each team a descriptive name and scope
- Records all employee names, first days, and team assignments in `.bureau/records/`
- Begins work toward the MVP
- Sets up the daily cron for continuous improvement once MVP is delivered
- Enforces version management (MVP = v1.0.0, subsequent releases follow semver)

## Human checkpoint

The human checkpoint between Stage 1 and Stage 2 is mandatory. The Bureau never proceeds to operational teams without explicit approval of the direction contract.

If the human annotates or rejects the contract, the founding team reconvenes to revise it before another approval cycle.
