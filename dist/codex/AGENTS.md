# manifest-dev Agents

## Workflow

This project uses a **define -> do -> verify -> done** workflow:

1. **define** -- Interview-driven manifest builder. Scopes the task, identifies acceptance criteria, global invariants, risks, and trade-offs. Supports `--interview` (minimal/autonomous/thorough), `--medium` (collaboration channel), `--amend` (modify existing manifest), and `--visualize` (interactive companion). Produces a manifest file.
2. **do** -- Manifest executor. Iterates through deliverables, implementing each according to the manifest. Supports `--mode` (efficient/balanced/thorough) for verification intensity. Handles mid-execution amendments when scope changes.
3. **verify** -- Spawns parallel verification agents to check acceptance criteria and invariants against the implementation. Runs in phases (faster checks first, slower later).
4. **done** -- Completion marker. Summarizes execution, notes any deviations, and closes the workflow.

**Supporting skills**:
- **auto** -- End-to-end autonomous execution that chains /define (autonomous interview) and /do into a single command.
- **escalate** -- Structured escalation for blocking issues, scope changes, and workflow pauses.
- **learn-define-patterns** -- Analyzes past /define sessions to extract user preference patterns and write them to AGENTS.md.

Skills handle the workflow orchestration. Agents listed below are specialized verification subagents spawned by the `verify` skill and supporting skills.

> **Codex CLI note**: On Codex, these agents are approximated using TOML config stubs in `agents/`. Codex agents have 6 default tools (`shell_command`, `apply_patch`, `update_plan`, `request_user_input`, `web_search`, `view_image`) plus experimental tools (`read_file`, `list_dir`, `grep_files`) that may be available depending on model configuration. Review agents use `sandbox_mode = "read-only"` to enforce read-only behavior.

---

## Verification Agent

### criteria-checker
Read-only verification agent. Validates a single acceptance criterion or global invariant using any automated method: shell commands, codebase analysis, file inspection, reasoning, or web research. Returns structured PASS/FAIL results with evidence. Core to the `verify` skill workflow -- spawned in parallel, one per criterion.

---

## Code Review Agents

### change-intent-reviewer
Adversarially analyzes whether code, prompt, or config changes achieve their stated intent. Reconstructs change intent from diff context, then systematically attacks the logic to find behavioral divergences -- where behavior won't match what the author expects. Produces a structured intent analysis report.

### code-bugs-reviewer
Audits code changes for mechanical defects -- runtime failures, resource issues, and structural code flaws. Focuses on defects detectable from code patterns (race conditions, resource leaks, edge cases, dangerous defaults, fail-loudly violations) rather than intent-behavior analysis. Produces a structured bug report with severity ratings (Critical/High/Medium/Low). Read-only: analyzes `git diff` output and source files without modifying anything.

### code-design-reviewer
Audits code for design fitness -- whether code is the right approach given what already exists in the framework, codebase, and configuration systems. Identifies reinvented wheels, misplaced responsibilities (code vs config boundary), under-engineering, short-sighted interfaces, concept misuse, and incoherent PR scope.

### code-simplicity-reviewer
Identifies unnecessary complexity, over-engineering, premature optimization, and cognitive burden. Catches solutions more complex than the problem requires -- not structural issues like coupling (handled by maintainability), but implementation complexity that makes code harder to understand than necessary.

### code-maintainability-reviewer
Comprehensive maintainability audit focusing on code organization: DRY violations, coupling, cohesion, consistency, dead code, architectural boundary leakage, concept drift, and migration debt. Examines how changes affect long-term codebase health.

### code-coverage-reviewer
Verifies that code changes have adequate test coverage by proactively enumerating edge cases from the code's logic. Analyzes the diff, derives specific test scenarios with concrete inputs and expected outputs, and reports coverage gaps.

### code-testability-reviewer
Identifies testability issues -- code requiring excessive mocking, business logic buried in IO operations, non-deterministic inputs, hidden dependencies, and tight coupling that makes verification difficult. Suggests structural improvements to reduce test friction.

### contracts-reviewer
Verifies API and interface contract correctness with evidence. Checks both outbound (code calls external/internal APIs correctly per documentation) and inbound (changes don't break consumers of your interfaces). Evidence-based -- cites actual API docs or codebase definitions.

### type-safety-reviewer
Audits code for type safety issues across typed languages (TypeScript, Python, Java/Kotlin, Go, Rust, C#). Identifies `any` abuse, invalid states representable in the type system, missing exhaustiveness checks, nullability gaps, and opportunities to push runtime checks into compile-time guarantees.

---

## Documentation and Compliance Agents

### docs-reviewer
Audits documentation and code comments for accuracy against recent code changes. Compares docs to code, producing a report of required updates without modifying files. Only reports issues with high confidence -- verified discrepancies between documentation and actual code behavior.

### context-file-adherence-reviewer
Verifies that code changes comply with context file (AGENTS.md) instructions and project standards. Focuses on outcome-based rules (code quality requirements) rather than workflow processes. Only reports violations with exact rule citations from the project context file.

---

## Define Workflow Agents

### manifest-verifier
Reviews manifests produced by the `define` skill for gaps that would cause implementation failure or rework. Returns specific questions to ask and areas to probe so the interview can continue. Validates completeness of acceptance criteria, invariants, assumptions, and risk areas.

### define-session-analyzer
Analyzes `define` session transcripts to extract user preference patterns -- what users push back on, consistently prefer, add unprompted, skip, or reject. These patterns become probing hints for future `define` sessions. Used by the `learn-define-patterns` skill. This is the only agent that requires write access (`sandbox_mode = "workspace-write"`).

---

## How to Use on Codex CLI

1. **Installed skills are namespaced** -- Use `$define-manifest-dev`, `$do-manifest-dev`, `$verify-manifest-dev`, `$done-manifest-dev`, `$escalate-manifest-dev`, `$auto-manifest-dev`, and `$learn-define-patterns-manifest-dev` via the Agent Skills Open Standard
2. **Multi-agent system** -- Enable with `[features] multi_agent = true` in `.codex/config.toml`. TOML stubs in `agents/` configure per-role behavior.
3. **Review agents are read-only** -- All review agents use `sandbox_mode = "read-only"` to prevent accidental modifications
4. **Spawn agents by role** -- When multi-agent is enabled, Codex can spawn agents with specific roles matching the TOML config names (e.g., `code-bugs-reviewer-manifest-dev`)
5. **Default tools available** -- All agents have access to 6 default tools: `shell_command`, `apply_patch`, `update_plan`, `request_user_input`, `web_search`, `view_image`
6. **Experimental tools** -- `read_file`, `list_dir`, `grep_files` may also be available depending on model configuration
7. **No hooks** -- Codex has no hook system (Issue #2109). The workflow chain is advisory -- nothing enforces completion order.
