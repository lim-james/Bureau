# Bureau Lifecycle

## Phases

The bureau operates in two distinct phases: **delivery** and **continuous improvement**. The transition between them is the MVP.

---

## Phase 1 — Delivery

### Milestone Planning
At the outset, the founding team defines milestones for the project. The first and most critical milestone is the **MVP** — a concrete, scoped endpoint that satisfies the core of the problem statement. The MVP is not the final word; it is the first deliverable.

- The MVP must be clearly defined before operational teams form
- It is the founding team's responsibility to set a realistic and meaningful MVP scope
- All operational teams orient their initial work toward the MVP

### Completion
The MVP marks the end of Phase 1. It is the bureau's first release — versioned and formally delivered.

### End-of-Phase Audit
Before any phase is considered closed, it is **recommended that the bureau stand up multiple consultancy teams to rigorously check every aspect of the project** — correctness, security, performance, coverage, documentation, and alignment with the direction contract. These teams audit with a critic's distance and leave once their findings are dispositioned. See [External Feedback](./feedback.md).

---

## Phase 2 — Continuous Improvement

The bureau does not stop at the MVP. Phase 2 is ongoing and self-directed.

### Daily Evaluation (Cron)
The bureau runs a daily cron job that triggers a full self-evaluation. Every employee role has a defined contribution to this cycle:

| Role | Contribution |
|------|-------------|
| **Researchers** | Search for better methods, tools, or approaches that could improve the project |
| **Developers** | Refactor, optimise, and improve the codebase |
| **Critics** | Evaluate code quality; may introduce or improve static analysis tooling |
| **Testers** | Ensure complete path coverage; surface any gaps in the test suite |
| **Partners** | Evaluate the bureau's overall position; determine if structural changes are needed |

This is not a passive review — every employee is expected to push the bureau forward. The cron job is the mechanism by which the bureau holds itself accountable to that expectation.

The daily cycle also reviews the [Backlog](./backlog.md) — outstanding work is drawn down by teams within their scope, so nothing owed is silently forgotten.

### Continuous Improvement Principles
- The bureau evaluates its own scope daily — nothing is assumed to be good enough
- Researchers operate outward-facing during this phase, actively seeking knowledge that could benefit the project
- No improvement is too small to be worthwhile if it genuinely advances the bureau

### External Feedback
The daily cron is the bureau's *internal* engine. External feedback — from the human or any outside source — is the *outward* counterpart and can arrive at any time. It is routed to partners, who deliberate on how it is accounted for. Feedback never blocks the cron, and the cron never supersedes feedback. See [External Feedback](./feedback.md).

---

## Version Management

All changes to the bureau's output are version-controlled. This is non-negotiable.

### Rules
- The MVP is the first official release — **v1.0.0**
- Every subsequent change that reaches a release threshold is versioned and formally rolled out
- Versioning follows [Semantic Versioning](https://semver.org/): `MAJOR.MINOR.PATCH`
  - `MAJOR` — breaking changes or significant scope shifts
  - `MINOR` — new features or meaningful improvements
  - `PATCH` — bug fixes, refactors, optimisations with no functional change
- No changes are deployed informally — all releases are intentional and recorded

### Release Process
1. Changes are developed and tested within teams
2. A release is proposed and reviewed (by critics and/or partners as appropriate)
3. Once approved, the release is versioned, tagged, and formally delivered
4. The bureau's continuous improvement cycle then begins again from the new baseline
