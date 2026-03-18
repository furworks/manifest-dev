# Definition: /auto Skill — End-to-End Autonomous Execution

## 1. Intent & Context
- **Goal:** Create a new `/auto` skill in the manifest-dev plugin that chains `/define --interview autonomous` → auto-approve → `/do`, enabling end-to-end autonomous execution for tasks that don't need human intervention during planning.
- **Mental Model:** `/auto` is a thin orchestration layer, not a new workflow. It composes two existing skills (`/define` and `/do`) with autonomous defaults. The full /define process still runs — all protocols, all probing, all logging — the only difference is the model answers its own questions. After the manifest is verified and summarized, /auto auto-approves and immediately launches /do.
- **Mode:** thorough

## 2. Approach

- **Architecture:** Single SKILL.md file in `skills/auto/SKILL.md`. Thin orchestrator that:
  1. Parses user input — extracts task description, optional `--mode` flag, rejects `--interview` if present
  2. Invokes `/define` with `--interview autonomous` prepended to the task description
  3. When /define presents the manifest summary, auto-approves (outputs summary for visibility but doesn't wait for user response) and proceeds immediately
  4. Invokes `/do` with the manifest path (+ `--mode` if specified by user)

- **Manifest path handoff:** /define's completion output follows the format `Manifest complete: /tmp/manifest-{timestamp}.md`. The SKILL.md instructs Claude to note this path from /define's output and pass it to /do. This is natural language instruction within a prompt — Claude reads /define's output and extracts the path. Verified: /define's SKILL.md "Complete" section confirms this output format.

- **Auto-approve mechanism:** /auto's SKILL.md tells Claude to treat /define's Summary for Approval as approved without asking the user. Since /auto's instructions frame the outer context, they guide behavior when /define's internal instructions would normally wait for user response. As a fallback, the SKILL.md should also instruct: "If the user is nevertheless asked for approval, proceed as if approved." If the user interrupts during autonomous /define (causing a dynamic style shift per INTERVIEW_STYLES.md), /define naturally becomes interactive — /auto's auto-approve becomes moot and the user engages directly.

- **Define failure handling:** If /define does not produce a manifest path (crash, context limit, or other failure), /auto must stop with an error message rather than attempting to invoke /do. The SKILL.md should include: "If /define does not output a manifest path, stop and report the failure."

- **Autonomous /define internals:** Verified in INTERVIEW_STYLES.md: autonomous mode auto-resolves all decisions including manifest-verifier CONTINUE responses. /auto does not need to handle the verifier loop — /define manages it internally.

- **Execution Order:**
  - D1 (SKILL.md) → D2 (plugin.json version bump) → D3 (README updates)
  - Rationale: SKILL.md is the core deliverable; plugin metadata and docs depend on it.

- **Risk Areas:**
  - [R-1] Auto-approve overrides a valid concern in the manifest summary | Detect: user interrupts /do with feedback that should have been caught at approval
  - [R-2] Composition conflict between /auto's "don't wait" and /define's "wait for approval" | Detect: Claude asks user for approval despite /auto's override instruction

- **Trade-offs:**
  - [T-1] User control vs automation → Prefer automation. Users who want control use /define + /do directly.
  - [T-2] Visibility vs speed → Prefer visibility. Show summary even though we don't wait on it.
  - [T-3] Brevity vs explicitness in SKILL.md → Prefer brevity. /auto is a thin orchestrator; trust /define and /do for the heavy lifting.

## 3. Global Invariants (The Constitution)

- [INV-G1] SKILL.md passes prompt-reviewer with no HIGH+ issues | Verify:
  ```yaml
  verify:
    method: subagent
    agent: prompt-reviewer
    prompt: "Review the prompt at claude-plugins/manifest-dev/skills/auto/SKILL.md against first-principles. Focus on clarity, conflicts, anti-patterns, invocation fit, and information density."
  ```

- [INV-G2] Skill description follows What + When + Triggers pattern (max 1024 chars) | Verify:
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: inherit
    prompt: "Read claude-plugins/manifest-dev/skills/auto/SKILL.md frontmatter. Verify: (1) description follows What + When + Triggers pattern, (2) under 1024 chars, (3) name is kebab-case and under 64 chars."
  ```

- [INV-G3] Existing project gates still pass (no Python breakage) | Verify:
  ```yaml
  verify:
    method: bash
    command: "cd /Users/aviram.kofman/Documents/Projects/manifest-dev && ruff check claude-plugins/ && black --check claude-plugins/ && mypy"
  ```

- [INV-G4] Documentation updated — all affected READMEs reflect the new /auto skill | Verify:
  ```yaml
  verify:
    method: subagent
    agent: docs-reviewer
    prompt: "Check that the /auto skill is documented in: (1) README.md (root), (2) claude-plugins/README.md, (3) claude-plugins/manifest-dev/README.md. Verify the skill is listed with accurate description."
  ```

- [INV-G5] Plugin version bumped (minor increment for new feature) | Verify:
  ```yaml
  verify:
    method: bash
    command: "cd /Users/aviram.kofman/Documents/Projects/manifest-dev && python3 -c \"import json; d=json.load(open('claude-plugins/manifest-dev/.claude-plugin/plugin.json')); v=d['version'].split('.'); assert int(v[1]) >= 66, f'Expected minor >= 66, got {v[1]}'\""
  ```

- [INV-G6] /auto does NOT duplicate /define or /do logic — it invokes them, not reimplements | Verify:
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: inherit
    prompt: "Read claude-plugins/manifest-dev/skills/auto/SKILL.md. Verify it invokes /define and /do via 'Invoke the manifest-dev:define/do skill' directives, NOT by inlining their logic. The skill should be a thin orchestrator."
  ```

- [INV-G7] Empty input produces error with usage hint, not a question | Verify:
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: inherit
    prompt: "Read claude-plugins/manifest-dev/skills/auto/SKILL.md. Verify it handles empty/missing arguments with an error message showing usage, NOT by asking the user a question."
  ```

- [INV-G8] --mode flag is passed through to /do invocation | Verify:
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: inherit
    prompt: "Read claude-plugins/manifest-dev/skills/auto/SKILL.md. Verify that when --mode is specified in arguments, it is passed to the /do invocation. Verify --interview autonomous is always forced for /define (not overridable by user)."
  ```

- [INV-G9] Autonomous mode clarification: /auto must NOT instruct /define to skip any protocols or probing — only --interview autonomous flag controls who answers questions | Verify:
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: inherit
    prompt: "Read claude-plugins/manifest-dev/skills/auto/SKILL.md. Verify the skill does NOT contain instructions to skip, shorten, or abbreviate /define's interview process. The only behavioral override should be: (1) forcing --interview autonomous, (2) auto-approving the manifest summary. The full /define process (domain grounding, pre-mortem, backcasting, etc.) must remain intact."
  ```

- [INV-G10] If user passes --interview flag, /auto rejects with an error (--interview is not supported, use /define for custom styles) | Verify:
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: inherit
    prompt: "Read claude-plugins/manifest-dev/skills/auto/SKILL.md. Verify it explicitly rejects/errors when --interview is passed as an argument, directing users to use /define for custom interview styles."
  ```

## 4. Process Guidance (Non-Verifiable)

- [PG-1] Document load-bearing assumptions — identify what must remain true for /auto to work (e.g., /define outputs manifest path in known format, /do accepts it as input).
- [PG-2] Keep the SKILL.md concise — /auto is a thin orchestrator, not a workflow definition. Trust /define and /do for complexity.
- [PG-3] Use the `prompt-engineering:prompt-engineering` skill before writing the SKILL.md to ensure first-principles prompt quality.

## 5. Known Assumptions

- [ASM-1] /define's `--interview autonomous` works correctly (auto-decides all questions, still runs all protocols) | Default: assume it works — established feature with defined behavior in INTERVIEW_STYLES.md, actively used in this project | Impact if wrong: /auto's core mechanism breaks
- [ASM-2] Skill invocation chaining works reliably (skill A invokes skill B) | Default: assume it works — established pattern used by /verify → /done, /do → /verify | Impact if wrong: /auto can't chain /define → /do
- [ASM-3] /do's escalation works independently of invocation source | Default: /do escalates via /escalate regardless of how it was launched | Impact if wrong: stuck /do with no escape path
- [ASM-4] Outer skill instructions (/auto) take precedence over inner skill instructions (/define) for the auto-approve step | Default: this follows natural prompt priority (most recent framing guides behavior) | Fallback: SKILL.md includes "if asked for approval, proceed as if approved" | Impact if wrong: Claude asks user for approval despite override — fallback instruction handles this

## 6. Deliverables (The Work)

### Deliverable 1: SKILL.md — /auto Skill Definition

**Acceptance Criteria:**
- [AC-1.1] SKILL.md exists at `claude-plugins/manifest-dev/skills/auto/SKILL.md` | Verify:
  ```yaml
  verify:
    method: bash
    command: "test -f /Users/aviram.kofman/Documents/Projects/manifest-dev/claude-plugins/manifest-dev/skills/auto/SKILL.md && echo 'File exists'"
  ```

- [AC-1.2] Skill parses input: `<task description> [--mode efficient|balanced|thorough]`. Errors on empty input with usage hint. | Verify:
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: inherit
    prompt: "Read claude-plugins/manifest-dev/skills/auto/SKILL.md. Verify input parsing handles: (1) task description extraction, (2) optional --mode flag extraction, (3) empty input → error with usage hint."
  ```

- [AC-1.3] Skill invokes `/define` with `--interview autonomous` and the user's task description | Verify:
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: inherit
    prompt: "Read claude-plugins/manifest-dev/skills/auto/SKILL.md. Verify it contains a directive to invoke manifest-dev:define with the user's task description AND --interview autonomous."
  ```

- [AC-1.4] After /define completes, skill outputs the manifest summary for user visibility but does NOT wait for approval — proceeds immediately | Verify:
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: inherit
    prompt: "Read claude-plugins/manifest-dev/skills/auto/SKILL.md. Verify it instructs to: (1) show the manifest summary to the user, (2) NOT wait for user approval/response, (3) immediately proceed to invoke /do."
  ```

- [AC-1.5] Skill invokes `/do` with the manifest path and optional --mode flag | Verify:
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: inherit
    prompt: "Read claude-plugins/manifest-dev/skills/auto/SKILL.md. Verify it contains a directive to invoke manifest-dev:do with the manifest file path from /define's output. If --mode was specified in original arguments, it must be passed to /do."
  ```

- [AC-1.6] Skill rejects --interview flag with error directing to /define | Verify:
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: inherit
    prompt: "Read claude-plugins/manifest-dev/skills/auto/SKILL.md. Verify it explicitly handles --interview flag in arguments by rejecting with an error message that directs users to use /define for custom interview styles."
  ```

- [AC-1.7] If /define does not output a manifest path, /auto stops with an error message rather than invoking /do | Verify:
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: inherit
    prompt: "Read claude-plugins/manifest-dev/skills/auto/SKILL.md. Verify it includes instructions to handle /define failure — if no manifest path is produced, /auto stops with an error rather than attempting to invoke /do."
  ```

### Deliverable 2: Plugin Metadata Update

**Acceptance Criteria:**
- [AC-2.1] Plugin version bumped to 0.66.0 in plugin.json | Verify:
  ```yaml
  verify:
    method: bash
    command: "cd /Users/aviram.kofman/Documents/Projects/manifest-dev && python3 -c \"import json; d=json.load(open('claude-plugins/manifest-dev/.claude-plugin/plugin.json')); assert d['version'] == '0.66.0', f'Expected 0.66.0, got {d[\\\"version\\\"]}'\""
  ```

- [AC-2.2] Keywords array in plugin.json includes "auto" | Verify:
  ```yaml
  verify:
    method: bash
    command: "cd /Users/aviram.kofman/Documents/Projects/manifest-dev && python3 -c \"import json; d=json.load(open('claude-plugins/manifest-dev/.claude-plugin/plugin.json')); assert 'auto' in d['keywords'], f'auto not in keywords: {d[\\\"keywords\\\"]}'\""
  ```

### Deliverable 3: Documentation Updates

**Acceptance Criteria:**
- [AC-3.1] Root README.md mentions /auto skill with accurate description | Verify:
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: inherit
    prompt: "Read README.md (root). Verify /auto is listed as a skill with a description that matches its actual behavior (end-to-end autonomous /define → /do)."
  ```

- [AC-3.2] claude-plugins/README.md updated if it lists individual skills | Verify:
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: inherit
    prompt: "Read claude-plugins/README.md. If it lists individual skills, verify /auto is included. If it only describes plugins at a high level, verify the manifest-dev description is still accurate."
  ```

- [AC-3.3] claude-plugins/manifest-dev/README.md lists /auto skill | Verify:
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: inherit
    prompt: "Read claude-plugins/manifest-dev/README.md. Verify /auto is listed among the plugin's skills with accurate description."
  ```
