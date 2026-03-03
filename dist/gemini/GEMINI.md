# manifest-dev

Verification-first manifest workflows. Use `/define` to plan, `/do` to execute, `/verify` to check, `/done` to complete.

## Workflow

1. **`/define`** — Interview-driven task scoping. Produces a manifest with deliverables, acceptance criteria, and invariants.
2. **`/do`** — Executes the manifest. Iterates through deliverables, tracking progress.
3. **`/verify`** — Spawns parallel verification agents to check all acceptance criteria and global invariants.
4. **`/done`** — Completion marker. Outputs hierarchical execution summary.
5. **`/escalate`** — Structured escalation when blocked.

## Agents

This extension includes 12 specialized agents for code review and verification. They are read-only auditors spawned by `/verify` to check specific quality dimensions (bugs, design, coverage, maintainability, simplicity, testability, type safety, docs, CLAUDE.md adherence).

## Key Files

- `skills/` — Workflow skills (define, do, verify, done, escalate, learn-define-patterns)
- `agents/` — Verification subagents
- `hooks/` — Workflow enforcement (stop blocking, verify reminders, compact recovery)
