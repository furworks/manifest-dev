# manifest-dev for Gemini CLI

Verification-first manifest workflows for Gemini CLI. Define tasks with acceptance criteria, execute against them, verify with parallel agents.

## Components

| Type | Count | Details |
|------|-------|---------|
| Skills | 6 | define, do, verify, done, escalate, learn-define-patterns |
| Agents | 12 | criteria-checker, manifest-verifier, 8 code reviewers, docs-reviewer, define-session-analyzer |
| Hooks | 3 | pretool-verify, stop-do-enforcement, post-compact-recovery |

## Install

### Option 1: Remote installer (recommended)

```bash
curl -fsSL https://raw.githubusercontent.com/doodledood/manifest-dev/main/dist/gemini/install.sh | bash
```

### Option 2: Skills only (via npx)

```bash
npx skills add https://github.com/doodledood/manifest-dev --all -a gemini-cli
```

### Option 3: Gemini extensions

```bash
gemini extensions install https://github.com/doodledood/manifest-dev/dist/gemini
# Or link locally:
gemini extensions link ./dist/gemini
```

## Required Configuration

Enable agents in your `~/.gemini/settings.json`:

```json
{
  "experimental": {
    "enableAgents": true
  }
}
```

Merge `hooks/hooks.json` into your settings.json hooks section for full workflow enforcement.

## Feature Parity

| Feature | Claude Code | Gemini CLI |
|---------|------------|------------|
| Skills (6) | Full | Full (copy unchanged) |
| Agents (12) | Full | Full (frontmatter converted) |
| Hooks (3) | Full | Full (adapter layer) |
| Subagent spawning | Agent tool | Named tool per agent |
| Todo management | TaskCreate/Update | write_todos |
| File search | Grep | grep_search |
| Web search | WebSearch | google_web_search |
| Skill invocation | Skill | activate_skill |
| Team management | TeamCreate/SendMessage | Not supported |
| Worktrees | EnterWorktree | Not supported |

## Hook Protocol Details

The adapter translates between Claude Code and Gemini CLI hook protocols:

| Hook | Claude Event | Gemini Event | Matcher | Exit Behavior |
|------|-------------|-------------|---------|---------------|
| pretool-verify | PreToolUse | BeforeTool | `activate_skill` (regex) | 0=allow, stdout=JSON with additionalContext |
| stop-do-enforcement | Stop | AfterAgent | (all) | 0=allow, 2=block (stderr=reason becomes new prompt) |
| post-compact-recovery | SessionStart | SessionStart | `resume` (exact match) | 0=allow, stdout=JSON with additionalContext |

Key protocol differences handled by the adapter:
- **Exit codes**: 0=allow (parse stdout), 1=warning, 2+=blocking (stderr=reason)
- **AfterAgent deny**: reason becomes a new prompt; clearContext clears LLM memory; stop_hook_active flags retry
- **Transcript format**: JSONL with "gemini" record type (patched to "assistant" for Claude hooks)
- **additionalContext**: Plain text (system-reminder XML tags stripped by adapter)

## Workflow

```
/define -> produces manifest with acceptance criteria
    |
/do -> executes against manifest, tracks progress
    |
/verify -> parallel verification with 12 specialized agents
    |
/done (all pass) or /escalate (blocked)
```

## Agent Tool Mapping

Tools were converted from Claude Code names to Gemini CLI equivalents:

| Claude Code | Gemini CLI |
|------------|------------|
| Bash / BashOutput | run_shell_command |
| Read | read_file |
| Write | write_file |
| Edit | replace |
| Grep | grep_search |
| Glob | glob |
| WebFetch | web_fetch |
| WebSearch | google_web_search |
| Skill | activate_skill |
| TaskCreate | write_todos |

## Repository

Main repo: [github.com/doodledood/manifest-dev](https://github.com/doodledood/manifest-dev)

This distribution is auto-generated from the Claude Code plugin source. See the main repo for documentation, issues, and contributions.
