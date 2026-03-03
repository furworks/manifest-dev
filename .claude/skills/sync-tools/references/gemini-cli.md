# Gemini CLI Conversion Guide

Reference for converting Claude Code plugin components to Gemini CLI format (v0.31.0 stable, March 2026).

## Conversion Summary

| Component | Phase 1 (Deterministic) | Phase 2 (LLM) |
|-----------|------------------------|----------------|
| Skills | Copy unchanged | — |
| Agents | Frontmatter conversion (tool map + add fields) | — |
| Hooks | Generate adapter + hooks.json config | Adapt complex hook logic |
| Commands | Convert to TOML format | — |
| Extension manifest | Generate gemini-extension.json | — |
| Context file | Rename CLAUDE.md → GEMINI.md | — |

## Phase 1: Deterministic Conversions

### Tool Name Mapping (Lookup Table)

| Claude Code Tool | Gemini CLI Tool | Notes |
|-----------------|-----------------|-------|
| Bash / BashOutput | `run_shell_command` | Requires approval |
| Read | `read_file` | 1-based lines (`start_line`/`end_line` params) |
| Write | `write_file` | Requires approval |
| Edit | `replace` | Uses `old_string`/`new_string` + `allow_multiple` |
| Grep | `grep_search` | Canonical name from source code. Docs index may show stale `search_file_content` — ignore that |
| Glob | `glob` | Same |
| WebFetch | `web_fetch` | Rate-limited |
| WebSearch | `google_web_search` | Google Search |
| Skill | `activate_skill` | Agent-only, not manually invocable |
| TodoWrite / TodoRead | `write_todos` | Single tool for both read and write |
| TaskCreate / TaskUpdate | `write_todos` | Task management maps to todos (single tool) |
| TaskGet / TaskList | `write_todos` | Task reads also via `write_todos` |
| TaskOutput | (no equivalent) | No background task output retrieval |
| TaskStop | (no equivalent) | No background task management |
| Agent | (subagent name as tool) | Subagents become tools by their registered name |
| AskUserQuestion | `ask_user` | Interactive dialog |
| EnterPlanMode | `enter_plan_mode` | Direct equivalent |
| ExitPlanMode | `exit_plan_mode` | Direct equivalent |
| EnterWorktree | (no equivalent) | No worktree support |
| TeamCreate / TeamDelete / SendMessage | (no equivalent) | No team management |
| ListMcpResourcesTool / ReadMcpResourceTool | (no equivalent) | MCP handled differently |

Gemini-only tools (no Claude Code equivalent):
- `list_directory` — directory listing with ignore/filter options
- `read_many_files` — read/concatenate multiple files (user-triggered via @ syntax)
- `save_memory` — saves facts to GEMINI.md
- `get_internal_docs` — Gemini CLI's own docs

Gemini built-in subagents (registered as tools by name):
- `codebase_investigator` — deep repo analysis subagent (enabled by default)
- `cli_help` — CLI help subagent (enabled by default)
- `generalist` — general-purpose subagent (enabled by default). NOTE: tool name is `generalist`, NOT `generalist_agent`
- `browser_agent` — web browser automation (experimental, disabled by default, requires Chrome 144+)

### Agent Frontmatter Conversion

Claude Code agent format:
```yaml
---
description: Agent purpose description
tools: Bash, Glob, Grep, Read, WebFetch, TaskCreate, WebSearch, BashOutput, Skill
model: inherit
---
```

Gemini CLI agent format:
```yaml
---
name: agent-name
description: Agent purpose description
kind: local
tools:
  - run_shell_command
  - glob
  - grep_search
  - read_file
  - web_fetch
  - google_web_search
  - activate_skill
  - write_todos
model: inherit
temperature: 0.2
max_turns: 15
timeout_mins: 5
---
```

**Complete Gemini CLI local agent frontmatter fields**:

| Field | Type | Required | Default | Valid Values |
|-------|------|----------|---------|--------------|
| `name` | string | Yes | — | Lowercase letters, numbers, hyphens, underscores |
| `description` | string | Yes | — | Free text |
| `kind` | string | No | `local` | `local`, `remote` |
| `tools` | string[] | No | all tools | List of internal tool names |
| `model` | string | No | `inherit` | Model ID or `inherit` |
| `temperature` | number | No | model default | 0.0 - 2.0 |
| `max_turns` | number | No | 15 | Positive integer |
| `timeout_mins` | number | No | 5 | Positive number |

**Phase 1 conversion rules** (deterministic):
1. Add `name` field from filename (lowercase, hyphens OK)
2. Keep `description` as-is
3. Add `kind: local`
4. Convert `tools` from comma-separated PascalCase string to YAML list of internal tool names
5. Deduplicate: BashOutput → run_shell_command (listed once). Map TaskCreate/TaskUpdate/TaskGet/TaskList → `write_todos`. Map Agent → (dropped — subagents are registered as named tools, not via a generic tool)
6. Set `model: inherit` (or specific Gemini model if needed)
7. Add `max_turns: 15` and `timeout_mins: 5` (defaults)
8. Keep prompt body unchanged
9. Write to `agents/` in extension directory

**Subagent mechanism**: Subagents become tools by name. A subagent `security-auditor` becomes callable as tool `security-auditor`. No generic `delegate_to_agent` tool.

**File locations**: Project `.gemini/agents/*.md`, User `~/.gemini/agents/*.md`, Extension `agents/*.md`.

**Activation**: Requires `"experimental": { "enableAgents": true }` in settings.json.

### Hook Conversion

Gemini CLI hooks use JSON stdin/stdout protocol similar to Claude Code.

**Event mapping (Claude Code → Gemini CLI)**:

| Claude Code Event | Gemini CLI Event | Can Block? | Notes |
|-------------------|-----------------|------------|-------|
| PreToolUse | `BeforeTool` | Yes (decision: deny) | Matcher: regex on tool names |
| PostToolUse | `AfterTool` | Yes (deny hides result) | Can chain tools via tailToolCallRequest |
| Stop | `AfterAgent` | Yes (deny forces retry) | Exit code 2 triggers retry |
| SessionStart | `SessionStart` | No (advisory) | source: startup/resume/clear |
| PreCompact | `PreCompress` | No (advisory) | trigger: auto/manual |
| Notification | `Notification` | No | notification_type, message, details |

Additional Gemini events (no Claude Code equivalent):
- `SessionEnd` — reason: exit/clear/logout
- `BeforeAgent` — after user prompt, before planning. Can block or inject context.
- `BeforeModel` — before LLM API request. Can mock LLM response.
- `AfterModel` — after LLM response chunk. Can replace chunk.
- `BeforeToolSelection` — filter available tools before model decides

**Protocol**:
- Input: JSON on `stdin`
- Output: JSON on `stdout` (NOTHING else — debug on stderr only)
- Exit code 0 = success, 2 = system block (stderr = reason), other = warning

**Universal input** (all events): `session_id`, `transcript_path`, `cwd`, `hook_event_name`, `timestamp`

**Universal output**: `systemMessage`, `suppressOutput`, `continue`, `stopReason`, `decision` (allow/deny/block), `reason`, `hookSpecificOutput`

**Event-specific details**:

`BeforeTool`: extra input `tool_name`, `tool_input`. Block: `decision: "deny"`. Modify args: `hookSpecificOutput.tool_input`.

`AfterTool`: extra input `tool_name`, `tool_response`. Hide result: `decision: "deny"`. Chain tool: `hookSpecificOutput.tailToolCallRequest: {name, args}`. Add context: `hookSpecificOutput.additionalContext`.

`AfterAgent`: extra input `prompt`, `prompt_response`. Force retry: `decision: "deny"`, reason becomes new prompt. Exit code 2: automatic retry.

`SessionStart`: extra input `source`. Inject context: `hookSpecificOutput.additionalContext`.

**Adapter pattern**: Claude Code Python hooks can be wrapped with a thin adapter:
- Claude `hookSpecificOutput.permissionDecision: "deny"` → Gemini `decision: "deny"`
- Claude `hookSpecificOutput.permissionDecisionReason` → Gemini `reason`
- Claude `hookSpecificOutput.additionalContext` → Gemini `hookSpecificOutput.additionalContext`

**Hook configuration** (`hooks/hooks.json`):
```json
{
  "hooks": {
    "BeforeTool": [
      {
        "matcher": "activate_skill",
        "sequential": true,
        "hooks": [
          {
            "type": "command",
            "command": "python3 ${extensionPath}/hooks/script.py",
            "name": "friendly-name",
            "timeout": 60000,
            "description": "Purpose"
          }
        ]
      }
    ]
  }
}
```

**Env vars**: `GEMINI_PROJECT_DIR`, `GEMINI_SESSION_ID`, `GEMINI_CWD`, `CLAUDE_PROJECT_DIR` (compat).

**Precedence**: Project > User > System > Extension hooks.

### Skills Handling

SKILL.md files copy unchanged. Only `name` and `description` frontmatter recognized. Claude Code extensions silently ignored.

**Discovery**: Workspace `.gemini/skills/` or `.agents/skills/` → User `~/.gemini/skills/` → Extensions `skills/`.

### Extension Manifest

Generate `gemini-extension.json`:
```json
{
  "name": "manifest-dev",
  "version": "0.1.0",
  "description": "Verification-first manifest workflows for Gemini CLI",
  "mcpServers": {},
  "excludeTools": [],
  "settings": []
}
```

### Context File

Rename CLAUDE.md → GEMINI.md. Supports `@file.md` imports. AGENTS.md configurable as alternative via `context.fileName` in settings.json.

## Extension Directory Structure

```
dist/gemini/
├── gemini-extension.json
├── GEMINI.md
├── agents/
│   ├── code-bugs-reviewer.md
│   └── criteria-checker.md
├── hooks/
│   ├── hooks.json
│   ├── gemini_adapter.py
│   ├── hook_utils.py
│   ├── stop_do_hook.py
│   ├── pretool_verify_hook.py
│   └── post_compact_hook.py
├── skills/
│   ├── define/
│   │   └── SKILL.md
│   └── do/
│       └── SKILL.md
└── README.md
```

## Installation

```bash
gemini extensions install https://github.com/<org>/<repo>/dist/gemini
# Or link locally:
gemini extensions link ./dist/gemini
```

Skills only: `npx skills add <url> --all -a gemini-cli`

Setup: `"experimental": { "enableAgents": true }` in settings.json. Merge hooks.json into settings.json hooks.

## Extensions Gallery

Automated publishing: public GitHub repo + `gemini-cli-extension` topic + `gemini-extension.json` at root → daily crawler → gallery at geminicli.com/extensions/browse/.

## Known Limitations

1. **Agents experimental** — Require enableAgents flag. API may change.
2. **No SubagentStart/Stop hooks** — Cannot intercept subagent lifecycle.
3. **Agent tool is name-based** — Each subagent becomes a tool by its registered name. No generic `delegate_to_agent` tool.
4. **Commands are TOML** — Not markdown.
5. **$ARGUMENTS not supported** — Claude Code extension only.
6. **`grep_search` is canonical** — Source code (`base-declarations.ts`) defines `GREP_TOOL_NAME = 'grep_search'`. The docs index page showing `search_file_content` is stale. Always use `grep_search`.
7. **`generalist` not `generalist_agent`** — The built-in subagent tool name is `generalist`, not `generalist_agent`.
8. **TaskCreate ≠ Agent** — Claude Code's TaskCreate/TaskUpdate/TaskGet/TaskList are todo management tools (map to `write_todos`), NOT subagent tools. Only `Agent` maps to subagent names.
