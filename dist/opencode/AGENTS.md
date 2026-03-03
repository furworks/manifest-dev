# manifest-dev

Verification-first manifest workflows. Use `/define` to plan, `/do` to execute, `/verify` to check, `/done` to complete.

## Workflow

1. **`/define`** — Interview-driven task scoping. Produces a manifest with deliverables, acceptance criteria, and invariants.
2. **`/do`** — Executes the manifest. Iterates through deliverables, tracking progress.
3. **`/verify`** — Spawns parallel verification agents to check all criteria.
4. **`/done`** — Completion marker with execution summary.
5. **`/escalate`** — Structured escalation when blocked.

## Agents

12 specialized read-only agents for code review and verification, spawned by `/verify`:
- **criteria-checker** — Validates single acceptance criteria (PASS/FAIL)
- **code-bugs-reviewer** — Logical bugs, race conditions, edge cases
- **code-coverage-reviewer** — Test coverage gaps
- **code-design-reviewer** — Design fitness, reinvented wheels
- **code-maintainability-reviewer** — DRY, coupling, cohesion
- **code-simplicity-reviewer** — Over-engineering, cognitive burden
- **code-testability-reviewer** — Testability issues, excessive mocking
- **type-safety-reviewer** — Type holes, invalid state representation
- **docs-reviewer** — Documentation accuracy
- **claude-md-adherence-reviewer** — Project standards compliance
- **manifest-verifier** — Manifest gap detection
- **define-session-analyzer** — User pattern extraction
