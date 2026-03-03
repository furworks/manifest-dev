# manifest-dev for OpenCode

Verification-first manifest workflows adapted for OpenCode. Define tasks, execute them, verify acceptance criteria, and complete with confidence.

## What's Included

| Component | Count | Status |
|-----------|-------|--------|
| Skills | 6 | Full compatibility (Agent Skills Open Standard) |
| Agents | 12 | Converted (frontmatter adapted, prompts unchanged) |
| Commands | 3 | From user-invoked skills (define, do, learn-define-patterns) |
| Hooks | — | TypeScript stubs + behavioral spec (manual port needed) |
| Context | AGENTS.md | Workflow overview + agent descriptions |

### Skills (copied unchanged)
- **define** — Manifest builder with interview-driven scoping
- **do** — Manifest executor, iterates through deliverables
- **verify** — Spawns parallel verification agents
- **done** — Completion marker with execution summary
- **escalate** — Structured escalation with evidence
- **learn-define-patterns** — Extracts user preference patterns from /define sessions

### Agents (converted frontmatter)
All 12 agents converted with OpenCode tool boolean format. Review agents are read-only verification subagents spawned by `/verify`.

### Hooks (stubs only)
The `plugins/` directory contains:
- **index.ts** — TypeScript plugin skeleton with correct event bindings and structure
- **HOOK_SPEC.md** — Complete behavioral specification for all three hooks
- **package.json** — Dependencies (`@opencode-ai/plugin`)

The Python hook logic must be manually ported to TypeScript. The spec documents the exact decision logic, transcript parsing, and edge cases.

## Install / Update

### One Command (recommended)
```bash
# From the dist/opencode directory:
bash install.sh
```

Installs skills, agents, commands, plugin stubs, and AGENTS.md. Idempotent — run again to update. Won't overwrite manually ported index.ts.

### Skills Only (works natively)
OpenCode reads `.claude/skills/` natively, so Claude Code skills already work without conversion:
```bash
npx skills add <github-url> --all -a opencode
```

### Manual
```bash
cp -r dist/opencode/skills/* .opencode/skills/
cp -r dist/opencode/agents/* .opencode/agents/
cp -r dist/opencode/commands/* .opencode/commands/
cp -r dist/opencode/plugins/* .opencode/plugins/
cp dist/opencode/AGENTS.md ./AGENTS.md
cd .opencode/plugins && bun install
```

## Feature Parity

| Feature | Status | Notes |
|---------|--------|-------|
| Skills (define/do/verify/done/escalate) | Full | Agent Skills Open Standard |
| Verification agents | Full | Frontmatter converted, prompts unchanged |
| Stop enforcement hook | Stub only | `session.idle` is NOT blocking in OpenCode |
| Verify context hook | Stub only | `tool.execute.before` binding correct |
| Post-compact recovery | Stub only | `experimental.session.compacting` — experimental |
| $ARGUMENTS in skills | Unknown | Behavior undefined in OpenCode |
| Notification hooks | Missing | No equivalent OpenCode event |

## Known Limitations

1. **Hooks require manual TypeScript port** — Python hooks can't run in Bun
2. **Stop hook cannot block** — `session.idle` is non-blocking (known gap)
3. **Native .claude/ compat** — Users may not need this dist for skills at all
4. **Plugin API may evolve** — OpenCode plugin API could change in future versions

## Source

This is a generated distribution from [manifest-dev](https://github.com/<org>/manifest-dev) for Claude Code. The Claude Code plugin is the source of truth.
