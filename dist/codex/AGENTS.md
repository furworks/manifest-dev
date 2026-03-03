# manifest-dev Agents

## Workflow

This project uses a **define → do → verify → done** workflow. Skills handle the workflow orchestration; agents listed below are specialized verification subagents spawned by `/verify`.

> **Note**: On Codex CLI, these agents cannot run as scoped subagents (Codex has only `shell` and `apply_patch` tools). The TOML config stubs in `agents/` approximate their roles using Codex's multi-agent system. Skills work fully.

## Verification Agents

- **criteria-checker**: Read-only verification agent. Validates a single acceptance criterion or global invariant using automated methods (commands, codebase analysis, file inspection, reasoning, web research). Returns structured PASS/FAIL results. Core to the `/verify` workflow.

## Code Review Agents

- **code-bugs-reviewer**: Audits code changes for logical bugs — race conditions, data loss, edge cases, logic errors. Produces structured bug reports with severity ratings.
- **code-coverage-reviewer**: Verifies that code changes have adequate test coverage. Identifies logic changes and reports coverage gaps.
- **code-design-reviewer**: Audits for design fitness — whether code is the right approach given existing framework, codebase, and configuration. Identifies reinvented wheels, misplaced responsibilities, under-engineering.
- **code-maintainability-reviewer**: Comprehensive maintainability audit — DRY violations, coupling, cohesion, consistency, dead code, architectural boundaries.
- **code-simplicity-reviewer**: Identifies unnecessary complexity, over-engineering, and cognitive burden — solutions more complex than the problem requires.
- **code-testability-reviewer**: Identifies testability issues — code requiring excessive mocking, business logic buried in IO, non-deterministic inputs, tight coupling.
- **type-safety-reviewer**: Audits for type safety issues across typed languages. Identifies type holes, opportunities to make invalid states unrepresentable, and ways to push runtime checks into compile-time guarantees.

## Documentation & Compliance Agents

- **docs-reviewer**: Audits documentation and code comments for accuracy against recent code changes. Reports required updates without modifying files.
- **claude-md-adherence-reviewer**: Verifies code changes comply with CLAUDE.md instructions and project standards.

## Define Workflow Agents

- **manifest-verifier**: Reviews `/define` manifests for gaps. Returns specific questions and areas to probe so the interview can continue.
- **define-session-analyzer**: Analyzes `/define` session transcripts to extract user preference patterns. Used by the `learn-define-patterns` skill.

## How to Use on Codex

These agents are primarily informational on Codex. For verification workflows:
1. Use the skills (`/define`, `/do`, `/verify`, `/done`) directly — they work via the Agent Skills Open Standard
2. For code review, use the TOML config stubs in `agents/` with Codex's multi-agent system (`[features] multi_agent = true`)
3. Review agents are read-only — set `sandbox_mode = "read-only"` in their TOML config
