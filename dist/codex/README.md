# manifest-dev for Codex CLI

Verification-first manifest workflows adapted for Codex CLI. Define tasks, execute them, verify acceptance criteria, and complete with confidence.

## What's Included

| Component | Count | Status |
|-----------|-------|--------|
| Skills | 6 | Full compatibility (Agent Skills Open Standard) |
| Agents | AGENTS.md + 12 TOML stubs | Informational + multi-agent config |
| Hooks | 0 | Not available (Codex has no hook system yet) |
| Execution rules | 1 | Starlark .rules file |
| Config | 1 | Multi-agent TOML config snippet |

### Skills (copied unchanged)
- **define** — Manifest builder with interview-driven scoping
- **do** — Manifest executor, iterates through deliverables
- **verify** — Spawns parallel verification agents
- **done** — Completion marker with execution summary
- **escalate** — Structured escalation with evidence
- **learn-define-patterns** — Extracts user preference patterns from /define sessions

### AGENTS.md
Describes all 12 agents, their purposes, and how to approximate their behavior using Codex's multi-agent system.

### TOML Agent Stubs
Per-agent TOML configuration files for Codex's multi-agent system. These approximate the Claude Code agents' roles but are limited to Codex's two tools (`shell` and `apply_patch`).

### Execution Rules
`rules/default.rules` provides safe defaults: allows read operations and tests, prompts for writes and git pushes.

## Install / Update

### One Command (recommended)
```bash
# From the dist/codex directory:
bash install.sh
```

Installs skills, AGENTS.md, agent TOML stubs, execution rules, and config. Idempotent — run again to update. Won't overwrite existing config.toml.

### Skills Only
```bash
npx skills add <github-url> --all

# Or Codex skill-installer (within session)
$skill-installer --repo <url> --path skills/<name>
```

### Manual
```bash
cp -r dist/codex/skills/* .agents/skills/
cp dist/codex/AGENTS.md ./AGENTS.md
mkdir -p .codex/agents && cp dist/codex/agents/*.toml .codex/agents/
mkdir -p .codex/rules && cp dist/codex/rules/default.rules .codex/rules/
# Merge dist/codex/config.toml into .codex/config.toml
```

## Feature Parity

| Feature | Status | Notes |
|---------|--------|-------|
| Skills (define/do/verify/done/escalate) | Full | Agent Skills Open Standard |
| Verification agents | TOML stubs | Limited to shell + apply_patch tools |
| Stop enforcement hook | Missing | No hook system in Codex (Issue #2109) |
| Verify context hook | Missing | No hook system |
| Post-compact recovery | Missing | No hook system |
| Workflow enforcement | Advisory | Without hooks, chain is not enforced |
| $ARGUMENTS in skills | Missing | Not supported by Codex CLI |
| Scoped subagents | Missing | Multi-agent uses global sandbox |

## Known Limitations

1. **Skills are the only fully compatible component** — agents are TOML stubs, hooks impossible
2. **No workflow enforcement** — without hooks, the define→do→verify→done chain is advisory
3. **Only 2 tools** — Codex agents have `shell` and `apply_patch` only
4. **No scoped subagents** — multi-agent uses global sandbox, no per-agent tool restriction
5. **Hooks expected soon** — Mid-March 2026 experimental release predicted (Issue #2109, 434+ upvotes)

When Codex ships hooks, this distribution should expand significantly.

## Source

This is a generated distribution from [manifest-dev](https://github.com/<org>/manifest-dev) for Claude Code. The Claude Code plugin is the source of truth.
