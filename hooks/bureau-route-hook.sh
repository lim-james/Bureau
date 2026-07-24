#!/usr/bin/env bash
#
# Bureau ROUTING hook. Registered as a Claude Code UserPromptSubmit command hook,
# so the harness runs it automatically on EVERY user prompt, before the model
# processes it. Its job is to make "being under the Bureau" a property of the
# PROJECT, not of the prompt: if the current project is a Bureau (it has a
# .bureau/ directory), this hook injects a routing mandate telling the model to
# act as the Bureau orchestrator — so the user never has to prefix prompts with
# /bureau, and prompts stop silently falling through to a single solo agent.
#
# Mechanism (confirmed against the Claude Code hooks docs): for UserPromptSubmit,
# a hook's PLAIN STDOUT on exit 0 is injected into the model's context for that
# turn. (We use plain stdout rather than the additionalContext JSON form to avoid
# a known VSCode-extension injection bug; plain stdout is the documented path and
# works in the CLI.) We NEVER exit 2 — that would BLOCK the prompt. This is a
# soft, injected mandate, not a sandbox interlock: it is honest about being an
# instruction the model follows, in the same class as the rest of today's Floor.
#
# It is a fast no-op in any project that is not a Bureau: it prints nothing and
# exits 0, so registering it globally costs nothing off-Bureau.
#
# Claude Code stdin schema for UserPromptSubmit is a JSON object on stdin; we do
# not need any field from it (routing depends only on the project dir), but we
# consume stdin regardless so the harness's pipe never blocks on a full buffer.
# The project root arrives as $CLAUDE_PROJECT_DIR.

set -uo pipefail

# Consume stdin regardless so the harness pipe never blocks; we don't parse it.
cat >/dev/null 2>&1 || true

# Which project is this? Prefer the harness-provided dir, fall back to cwd.
CWD="${CLAUDE_PROJECT_DIR:-$PWD}"

# Detection: only Bureau projects are routed. No .bureau/ -> silent no-op, and
# plain (non-Bureau) Claude behaviour is preserved untouched.
[ -d "$CWD/.bureau" ] || exit 0

# This project IS a Bureau. Inject the routing mandate. Everything printed to
# stdout below becomes context for this turn.
cat <<'MANDATE'
=== BUREAU ROUTING MANDATE (auto-injected; this project is under the Bureau) ===
This project contains a `.bureau/` directory, so it is a Bureau. Every prompt
here is a Bureau prompt — `/bureau` is NOT required and never needs to be typed.
You are the Bureau ORCHESTRATOR for this turn, not a solo assistant. Constitution
is law: read `.bureau/constitution/` (esp. operating_principles.md, foundation.md,
routing.md) as needed.

1) COMPLEXITY GATE — classify this request first:
   • TRIVIAL — a typo/one-line edit, a single-file lookup, a direct factual
     question about existing state, a quick clarification. Handle it DIRECTLY, no
     teams. (Spawning a quorum for trivia violates operating_principles.md L-01 —
     agents must earn their cost.)
   • SUBSTANTIVE — any feature, design, refactor, investigation, multi-file or
     multi-step work, or anything where correctness is load-bearing. You MUST
     convene the pipeline (below) before concluding.

2) QUORUM FLOOR (substantive work) — convene at least 2 TEAMS of >=3 named agents
   each, spawned via the Agent tool and run IN PARALLEL. At least one agent must
   be an INDEPENDENT ADVERSARIAL VERIFIER. Per operating_principles.md A-1/A-2:
   agent agreement is NOT evidence (same-model errors are correlated). Coverage
   comes from decomposition; CORRECTNESS comes from grounding every load-bearing
   claim in something the model cannot author — a test, a tool, an executed
   command, or a primary source — never from consensus.

3) RECORDS — honour standing obligations: write team records to
   `.bureau/records/teams/`, a Why-Ledger entry at each settled call
   (schema in constitution/decisions.md), and Tooling Workshop discipline
   (search the index before building durable tooling).

4) HUMAN OVERRIDE — if the human explicitly says "just answer", "no bureau",
   "quick", or similar for this prompt, respect it and answer directly. Human
   authority outranks the mission; do not force a quorum against an explicit
   instruction.

Note: this mandate is an injected instruction you are expected to follow, not a
harness-enforced interlock. Follow it in good faith.
=== END BUREAU ROUTING MANDATE ===
MANDATE

exit 0
