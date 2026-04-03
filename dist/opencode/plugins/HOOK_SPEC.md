# Hook Behavioral Specification

This document describes the exact behavior implemented in `index.ts` and serves as the maintenance reference for the OpenCode hook adaptation from `claude-plugins/manifest-dev/hooks/`.

Corrected for OpenCode v1.2.15 (March 2026). See `.claude/skills/sync-tools/references/opencode-cli.md` for the full conversion reference.

## Hook Mapping

| Claude Code Hook | Source File | OpenCode Event | Can Block? |
|-----------------|-------------|----------------|------------|
| Stop | `stop_do_hook.py` | `session.idle` (event) | **NO** — fire-and-forget |
| PreToolUse/Skill | `pretool_verify_hook.py` | `tool.execute.before` | Yes — throw Error |
| SessionStart/compact | `post_compact_hook.py` | `experimental.session.compacting` | No — inject context only |
| UserPromptSubmit | `prompt_submit_hook.py` | `experimental.chat.system.transform` | No — inject system messages |
| UserPromptSubmit | `understand_prompt_hook.py` | `experimental.chat.system.transform` | No — inject system messages |
| PostToolUse | `posttool_log_hook.py` | `tool.execute.after` | No — mutate output |

## 1. Stop Enforcement (`stop_do_hook.py` → `session.idle`)

### Behavior

When the session stops during an active /do workflow, attempt to re-engage the agent unless a proper exit condition is met.

### Decision Matrix

| Condition | Action |
|-----------|--------|
| No /do active | Do nothing |
| /do + /done | Do nothing (properly completed) |
| /do + /escalate (non-self-amendment) | Do nothing (properly escalated) |
| /do + self-amendment | Attempt re-engage with amendment message |
| /do + /verify + non-local medium | Do nothing (escalation posted externally) |
| /do without exit | Attempt re-engage with enforcement message |
| 3+ consecutive short outputs | Do nothing — break loop, log warning |

### Limitations

- **Cannot block stopping.** `session.idle` is fire-and-forget. The workaround `ctx.client.session.prompt()` creates a NEW conversation turn, not a continuation. It is fragile with race conditions in `run` mode (issue #15267).
- **Feature request exists** for blocking `session.idle` (issue #12472).

## 2. Verify Context Injection (`pretool_verify_hook.py` → `tool.execute.before` + `experimental.chat.system.transform`)

### Behavior

When /verify is about to be called, inject a system-level reminder to read the manifest and execution log in full before spawning verifiers.

### Implementation

1. `tool.execute.before` detects when the `task` tool targets the `verify` skill
2. Stores a pending verify reminder
3. `experimental.chat.system.transform` pushes the reminder to `output.system[]` on the next LLM request
4. Reminder is cleared after injection (one-shot)

### Limitations

- **Subagent bypass:** `tool.execute.before` does NOT fire for tool calls within subagents (issue #5894). If /verify is called from within a subagent, the reminder will not trigger.

## 3. Post-Compact Recovery (`post_compact_hook.py` → `experimental.session.compacting`)

### Behavior

When the session compacts during an active /do workflow, inject recovery context reminding the agent to re-read the manifest and execution log.

### Decision Logic

| Condition | Action |
|-----------|--------|
| No /do active | Do nothing |
| /do completed (/done or /escalate) | Do nothing |
| Active /do with args | Inject reminder with /do args |
| Active /do without args | Inject fallback reminder |

### Limitations

- **Experimental API.** `experimental.session.compacting` may change without notice.

## 4. Amendment Check (`prompt_submit_hook.py` → `experimental.chat.system.transform`)

### Behavior

During an active /do workflow, inject an amendment check reminder before every LLM request. This tells the agent to check whether user input contradicts, extends, or amends the manifest.

### Decision Logic

| Condition | Action |
|-----------|--------|
| No /do active | Do nothing |
| /do completed (/done) | Do nothing |
| Active /do | Inject amendment check reminder |

### Limitations

- **Fires on every LLM request,** not just user messages. This is broader than Claude Code's UserPromptSubmit which fires only on user input. The overhead is acceptable since the reminder is small.
- **Experimental API.** `experimental.chat.system.transform` may change without notice.

## 5. Post-Tool Log Reminder (`posttool_log_hook.py` → `tool.execute.after`)

### Behavior

After milestone tool calls during an active /do workflow, append a log reminder to the tool output. This nudges the agent to update the execution log.

### Target Tools

| Tool | Condition |
|------|-----------|
| `todowrite` | Always (task management milestones) |
| `task`/`skill` | Only for workflow skills: verify, escalate, done, define |

### Limitations

- **Subagent bypass:** `tool.execute.after` does NOT fire for tool calls within subagents (issue #5894). Log reminders for tools called by criteria-checker or other subagents will not trigger.
- **Mutates output:** The reminder is appended to `output.output` as a `<system-reminder>` tag. If the output is not a string, the reminder is skipped.

## 6. Understand Principles Reinforcement (`understand_prompt_hook.py` → `experimental.chat.system.transform`)

### Behavior

During an active /understand session, inject a concise principles reminder before every LLM request. This combats sycophantic drift and premature convergence over long conversations.

### Decision Logic

| Condition | Action |
|-----------|--------|
| No /understand active | Do nothing |
| /understand completed (/understand-done or workflow skill invoked) | Do nothing |
| Active /understand | Inject principles reminder |

### Limitations

- **Fires on every LLM request,** not just user messages. Broader than Claude Code's UserPromptSubmit but overhead is minimal (short reminder text).
- **Experimental API.** `experimental.chat.system.transform` may change without notice.

## 7. Understand Compaction Recovery (`post_compact_hook.py` → `experimental.session.compacting`)

### Behavior

When the session compacts during an active /understand session, inject recovery context reminding the agent to re-read the /understand skill and restore its cognitive stance.

### Decision Logic

| Condition | Action |
|-----------|--------|
| No /understand active | Do nothing |
| /understand completed | Do nothing |
| Active /understand with args | Inject reminder with /understand args |
| Active /understand without args | Inject fallback reminder |

## Workflow State Tracking

Claude Code hooks parse the session transcript (JSONL) to detect workflow state. OpenCode stores sessions in SQLite with no JSONL equivalent.

**Replacement approach:** In-memory state tracking within the plugin.

The `DoFlowState` object tracks:
- `/do` invocation (resets all state)
- `/verify`, `/done`, `/escalate` calls after `/do`
- Self-amendment escalations
- Collaboration mode (`--medium` flag)

The `UnderstandFlowState` object tracks:
- `/understand` invocation (resets understand state)
- `/understand-done` calls (explicit completion)
- Workflow skill invocations that implicitly end /understand (`/define`, `/do`, `/auto`)

**Limitation:** Plugin state is ephemeral — lost on plugin reload or server restart. For long-running sessions that survive server restarts, state would need to be persisted to disk or reconstructed from the SDK client API.

## Loop Detection

Consecutive short outputs (< 100 chars, no meaningful tool use) are tracked to detect infinite loops where the agent tries to stop but keeps getting re-engaged. After 3+ consecutive short outputs, the stop hook allows the session to end.

## Active /do Enforcement

A soft enforcement message is injected via `experimental.chat.system.transform` during every active /do workflow, reminding the agent that it must complete via /verify or /escalate. This supplements the stop hook's re-engagement (which may not fire due to the fire-and-forget limitation).
