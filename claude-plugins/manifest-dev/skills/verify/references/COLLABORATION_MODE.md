# Collaboration Mode — /verify

This file is loaded when `--medium` is not `local` OR when `$ARGUMENTS` contains a `TEAM_CONTEXT:` block. Two routing modes exist: **direct medium** (--medium flag, single-agent) and **team mode** (TEAM_CONTEXT, multi-agent). If neither condition is met, this file should not have been loaded.

## Mode Detection

- `TEAM_CONTEXT:` block present → **Team mode** (see Team Mode section below)
- `--medium slack` without TEAM_CONTEXT → **Direct Slack mode** (see Direct Slack Mode below)

---

## Direct Slack Mode

When `--medium` is not `local` and no TEAM_CONTEXT is present, /verify operates normally (spawns agents, runs verification locally). The only addition:

**Post results to Slack.** After verification completes, post a summary of results to the Slack channel referenced in the manifest's PG items. Include: phase results, pass/fail counts, failure details if any.

**Everything else unchanged.** All principles from SKILL.md apply: orchestrate don't verify, all criteria no exceptions, globals are critical. Verification runs locally as normal.

---

## Team Mode

When `$ARGUMENTS` contains a `TEAM_CONTEXT:` block, verification delegates to the team lead instead of spawning agents locally.

### Override When Active

**Do NOT spawn agents or run verification checks.** In team mode, the executor teammate cannot spawn other teammates (Claude Code limitation). Instead:

1. Extract all criteria (INV-G* and AC-*) from the manifest with their verification methods.
2. Return the full criteria list to the calling skill (/do) indicating delegation is needed.
3. /do will send the VERIFICATION_REQUEST to the lead via SendMessage. You do not send messages yourself.

**Why /do sends, not /verify**: /verify runs as a nested skill inside /do. SendMessage may not be reliably available in a skill-within-a-skill context. /do, running directly in the teammate context, has SendMessage access.

### VERIFICATION_REQUEST Format

The criteria list you return to /do should contain all information the lead needs to spawn verification teammates:

```
VERIFICATION_REQUEST:
  manifest_path: <path>
  log_path: <path>
  criteria:
    - id: INV-G1
      description: "..."
      method: bash | codebase | subagent
      command: "..." (if bash)
      agent: "..." (if subagent)
      prompt: "..." (if codebase/subagent)
    - id: AC-1.1
      description: "..."
      method: bash
      command: "..."
    ...
```

Include ALL criteria — INV-G* and AC-*. Skipping any criterion is a critical failure (same as solo mode).

### Everything Else Unchanged

All principles from SKILL.md apply: orchestrate don't verify, all criteria no exceptions, globals are critical. The only change is WHERE verification happens (lead-spawned teammates instead of locally-spawned agents).
