# Hook Behavioral Specification

This document describes the intended behavior of each hook from the Claude Code manifest-dev plugin. Use this as a reference when implementing the TypeScript plugin stubs in `index.ts`.

## Hook 1: Verify Context Reminder

**Claude Code event**: PreToolUse (matcher: Skill)
**OpenCode event**: `tool.execute.before` (check tool === "skill")

**Behavior**:
- Triggers when the Skill tool is called with skill name "verify" or "*:verify"
- Injects a system reminder telling Claude to read the manifest and execution log in FULL before spawning verifiers
- Does NOT block the tool call — only adds context
- If the skill has arguments (e.g., a specific manifest path), includes them in the reminder

**Key logic** (from `pretool_verify_hook.py`):
1. Check `tool_name === "Skill"` and `tool_input.skill` matches "verify" or ends with ":verify"
2. Extract `tool_input.args` if present
3. Output `additionalContext` with a reminder template

## Hook 2: Stop/Do Workflow Enforcement

**Claude Code event**: Stop
**OpenCode event**: `session.idle` (partial — NOT blocking in OpenCode)

**Behavior**:
- Blocks premature session stops during active /do workflows
- Decision matrix:
  - API error (last assistant message has `isApiErrorMessage=true`) → ALLOW
  - No /do in transcript → ALLOW
  - /do + /done → ALLOW (verified complete)
  - /do + /escalate → ALLOW (properly escalated)
  - /do only → BLOCK (must verify first)
  - /do + /verify only → BLOCK (verify may have found failures)
- Infinite loop detection: If 3+ consecutive short assistant outputs (<100 chars, no meaningful tool use), ALLOW with warning to break the loop
- Short outputs include attempted /escalate calls (Skill tool uses don't count as "meaningful")

**Key logic** (from `stop_do_hook.py` + `hook_utils.py`):
1. `has_recent_api_error(transcript_path)` — check last assistant for API errors
2. `parse_do_flow(transcript_path)` — returns DoFlowState with has_do, has_verify, has_done, has_escalate
3. `count_consecutive_short_outputs(transcript_path)` — loop detection

**OpenCode limitation**: `session.idle` cannot block the session from stopping. This is a known gap. Consider alternative approaches:
- Use `tool.execute.before` on ALL tools to check workflow state and inject reminders
- Use a custom tool that the agent must call before completing

## Hook 3: Post-Compact Recovery

**Claude Code event**: SessionStart (triggered after compaction)
**OpenCode event**: `experimental.session.compacting`

**Behavior**:
- Detects when session compaction occurs during an active /do workflow
- Injects a reminder to re-read the manifest and execution log
- Only activates if /do was invoked but neither /done nor /escalate was called
- Includes the original /do arguments in the reminder if available

**Key logic** (from `post_compact_hook.py` + `hook_utils.py`):
1. `parse_do_flow(transcript_path)` — check for active /do workflow
2. If `state.has_do` and not `state.has_done` and not `state.has_escalate`:
   - Build recovery reminder with `state.do_args` if available
   - Output `additionalContext` with the reminder

## Transcript Parsing (hook_utils.py)

The hooks depend on `hook_utils.py` for transcript parsing. Key functions:

### `parse_do_flow(transcript_path) → DoFlowState`
Reads JSONL transcript line by line. Tracks:
- `/do` invocations (resets flow state on each new `/do`)
- `/verify`, `/done`, `/escalate` after the most recent `/do`
- Detects skill invocations via three patterns:
  1. Assistant Skill tool_use blocks
  2. User isMeta skill expansions
  3. User command-name tags

### `count_consecutive_short_outputs(transcript_path) → int`
Counts consecutive short assistant outputs from end of transcript.
"Short" = <100 chars text AND no meaningful tool uses (Skill calls excluded).

### `has_recent_api_error(transcript_path) → bool`
Checks if the last assistant message has `isApiErrorMessage=true`.

## Implementation Notes

- All hooks read the JSONL transcript file at `transcript_path`
- Transcript format: one JSON object per line, with `type` (user/assistant/tool_result)
- Claude Code hooks use JSON stdout for output; OpenCode uses return values from event handlers
- When porting, replace `sys.stdin` JSON parsing with function parameters and `print(json.dumps(...))` with return values
