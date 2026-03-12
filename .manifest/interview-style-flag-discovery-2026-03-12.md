# Discovery Log: Interview Style Flag for /define

## Task
Add `--interview <level>` flag to /define with 3 levels controlling interview questioning threshold.

## Interview Style: thorough (default — full probing)

## Domain Grounding

### Existing Patterns Found
- /do parses `--mode <level>` from `$ARGUMENTS` — same pattern for `--interview`
- BUDGET_MODES.md controls verification intensity — unrelated to interview style
- Complexity triage (Simple/Standard/Complex) is orthogonal — controls which protocols run
- Fast-track signal ("just build it") — folding into autonomous level

### Key Design Decisions (User-Confirmed)
1. Flag syntax: `--interview <level>` (minimal | autonomous | thorough)
2. Default: thorough (current behavior, zero changes to default path)
3. All protocols still run at every level — style controls WHO decides, not WHAT's covered
4. Minimal: ask scope, constraints, high-impact items; auto-decide rest
5. Autonomous: no AskUserQuestion; all decisions auto-resolved; present manifest for approval
6. Auto-decided items: encoded normally with "(auto)" annotation + listed in Known Assumptions
7. No manifest schema changes — interview style in discovery log only
8. Verifier follows execution mode, not interview style
9. BUDGET_MODES.md unchanged
10. Fast-track signal folded into autonomous (one mechanism, not two)
11. Principles per level (not exhaustive rules) — manages prompt length
12. Full delivery: SKILL.md + version bump + READMEs
13. Orthogonal to complexity triage — both apply independently
14. Style is dynamic — set via flag but shifts if user explicitly requests more/less probing
15. Autonomous rejection: agent auto-resolves, doesn't switch to interactive mode

## Resolved Items

### Task File Quality Gates
- [x] PROMPTING.md: Clarity → INV-G4
- [x] PROMPTING.md: No conflicts → INV-G6
- [x] PROMPTING.md: Structure → INV-G14
- [x] PROMPTING.md: Information density → INV-G7
- [x] PROMPTING.md: No anti-patterns → INV-G5
- [x] PROMPTING.md: Invocation fit → INV-G11
- [x] PROMPTING.md: Domain context → SKIPPED (domain is the /define workflow itself, fully understood from codebase exploration)
- [x] PROMPTING.md: Complexity fit → INV-G12
- [x] PROMPTING.md: Memento → SKIPPED (not adding a multi-phase workflow, adding a flag to an existing one)
- [x] PROMPTING.md: Description → SKIPPED (not creating a new skill, modifying existing /define)
- [x] PROMPTING.md: Edge case coverage → INV-G13
- [x] PROMPTING.md: Model-prompt fit → SKIPPED (no new model-specific capabilities required; interview style uses existing AskUserQuestion mechanism)
- [x] PROMPTING.md: Guardrail calibration → SKIPPED (no safety boundaries involved; interview style is a user preference)
- [x] PROMPTING.md: Output calibration → SKIPPED (output format unchanged per INV-G2)
- [x] CODING.md quality gates → SKIPPED (ASM-5: no executable code changes)
- [x] FEATURE.md quality gates → INV-G1 (regression), INV-G6 (conflict check)
- [x] CODING.md project gates → INV-G8 (lint, format, typecheck)

### Task File Defaults
- [x] FEATURE.md "Document load-bearing assumptions" → PG-1

### Resolvable Items
- [x] PROMPTING.md context to discover → Resolved: domain knowledge (define workflow), user types (define users), integration context (flag in argument parsing)
- [x] PROMPTING.md risks → INV-G1 (regression), INV-G6 (composition conflict), R-3 (context rot)
- [x] PROMPTING.md trade-offs → T-1 (specificity vs brevity: prefer principles), T-2 (new flag vs overloading mode)
- [x] PROMPTING.md anti-patterns → INV-G5 (no anti-patterns invariant)
- [x] CODING.md scenario prompts → SKIPPED (no executable code changes)
- [x] FEATURE.md risks → Scope creep (kept focused), breaking consumers (INV-G9)
- [x] FEATURE.md scenario prompts → Mental model mismatch (clarified: who decides, not what's covered), backward compat (INV-G1, INV-G2)
- [x] FEATURE.md trade-offs → Scope vs time (full delivery), flexibility vs simplicity (principles per level)

### Pre-Mortem Scenarios
- [x] Regression: thorough default changes unintentionally → INV-G1
- [x] Composition conflict with complexity triage → INV-G6, design is orthogonal
- [x] Context rot from prompt additions → R-3, PG-2
- [x] Fast-track removal gap → R-4, autonomous covers the use case
- [x] Breaking /do and /verify → INV-G9
- [x] User confusion about autonomous Known Assumptions → AC-1.3, dual tracking
- [x] Autonomous manifest rejection → AC-1.8, agent auto-resolves
- [x] Mid-interview style shift → AC-1.7, style is dynamic

### Outside View
- [x] Reference class: "Adding optional flag to LLM prompt/skill". Common failures: flag changes default behavior, flag adds too much complexity, flag creates contradictions. → INV-G1, INV-G6, PG-2

### Backcasting
- [x] AskUserQuestion tool exists and can be conditionally skipped → Safe
- [x] Known Assumptions section already in manifest schema → Safe
- [x] Argument parsing can be added without breaking task description parsing → Safe (same pattern as /do)
