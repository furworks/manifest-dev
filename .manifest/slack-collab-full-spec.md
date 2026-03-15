# Slack-Collab Full Specification

*Living spec for the manifest-dev-collab plugin. Run `/do .manifest/slack-collab-full-spec.md` to verify all criteria and fix regressions.*

## 1. Intent & Context

- **Goal:** Collaborative define/do workflow via Slack using Agent Teams — seamless enough to handle real sessions (bot comment triage, CI failure classification, lean polling, lead orchestration) without human intervention for routine decisions.

- **Mental Model:**
  - **Lead** = the `/slack-collab` skill session. Orchestrator with voice — manages phases, writes state file, acts as subagent bridge, and contributes to discussions (answers when referenced, surfaces conflicts, fact-checks claims). **NEVER uses Slack MCP tools directly** — all Slack interaction routes through the slack-coordinator. **Sends context and instructions to coordinators — never composes verbatim messages.** Unnamed voice (no system attribution prefix). Role hierarchy: lead = orchestrator, humans = advisors, owner = override power. Must create team via `TeamCreate` before spawning any teammates. Verifies Agent Teams availability (ToolSearch for TeamCreate + SendMessage) before Phase 0 — aborts if unavailable. Terminates all teammates via shutdown_request in Phase 6.
  - **slack-coordinator** (sonnet model, spawned via `subagent_type: manifest-dev-collab:slack-coordinator`) = dedicated Slack I/O teammate. Posts messages, sends DMs, polls threads and DM conversations, routes stakeholder answers to lead. Continuous split-sleep polling at 60-second intervals (two 30s halves with mailbox check between) — starts after first thread, runs until shutdown_request. Checks for lead messages 3 times per poll cycle (before polling, after polling, mid-sleep). Each item (question, review, phase transition) gets its own parent message in the main channel (no mega-thread). Tags only relevant stakeholders per thread. Disambiguates pronouns when relaying messages (replaces "you"/"me"/"us" with specific names/roles). Responds honestly to identity questions about lead's contributions (AI orchestrator) only when directly asked. Lean diff-only reporting — uses `last_seen_ts` per thread, reports only new messages since last poll. Recovers from compaction via state file.
  - **define-worker** (spawned via `subagent_type: manifest-dev-collab:define-worker`, model omitted = inherits parent) = runs `/define` with TEAM_CONTEXT. Messages lead for all communication (stakeholder Q&A routed through lead -> coordinator). Requests verification subagent launches from lead. Persists as manifest authority for QA evaluation AND Phase 4 PR comment evaluation (classifies comments, amends manifest for valid gaps, explains drops).
  - **executor** (spawned via `subagent_type: manifest-dev-collab:executor`, model omitted = inherits parent) = MUST invoke `/do` via Skill tool (never implement directly). Messages lead for escalations (routed through lead -> coordinator). Runs /verify locally (has all tools inherited from lead, including Agent tool for spawning criteria-checkers). Creates PR. Fixes QA issues routed through lead. Contains redundant guard: rejects PR review issues without AC references from define-worker.
  - **github-coordinator** (sonnet model, spawned via `subagent_type: manifest-dev-collab:github-coordinator`) = dedicated GitHub I/O teammate. Polls PR reviews, comments, CI status. Spawned in Phase 4 after PR creation. Same split-sleep polling pattern as slack-coordinator (60s, lean diffs, state recovery). Distinguishes bot vs human comment authors in reports. Recovers from compaction via state file. **Initial actions at spawn**: requests formal PR reviews via `gh pr edit --add-reviewer` and posts initial PR comment tagging reviewers (when GitHub handles are provided).
  - **Hub-and-spoke** = all teammate communication flows through the lead. No direct teammate-to-teammate messaging. The lead is the communication hub.
  - **Subagent bridge** = define-worker requests manifest-verifier launches from lead. Subagents send results directly to the requesting worker via SendMessage (if feasible) or write to `/tmp/subagent-result-{id}.md` and lead tells worker the file path (fallback). Exception: executor runs /verify locally and spawns its own criteria-checkers — verification doesn't go through the bridge.
  - **TEAM_CONTEXT** = behavior switch. Tells `/define` and `/do` to message the lead instead of using AskUserQuestion. Format includes `lead` name, `coordinator` name, and `role`.
  - **State file** = crash/resume recovery. JSON at `/tmp/collab-state-{run_id}.json`. Written by lead (single writer) after phase transitions and thread updates. Includes per-thread `last_seen_ts` for diff polling recovery. Supports mid-phase resume.
  - **Active polling** = coordinators poll continuously with 60-second split-sleep cycles (sleep 30 -> check mailbox -> sleep 30). Lean diff-only: read only new messages since `last_seen_ts`. On compaction/respawn, recover from state file. 24-hour timeout before escalating unanswered questions to owner.
  - **User comms after Phase 0** = once the team is spawned, ALL user communication goes through the slack-coordinator -> Slack. No terminal output or AskUserQuestion during the workflow. Only exception: coordinator failure escalation.
  - **Channel** = user-provided. No channel creation or invite available in Slack MCP. User must create channel and ensure stakeholders are members before starting.

- **TEAM_CONTEXT Format:**
  ```
  TEAM_CONTEXT:
    lead: <lead-name>
    coordinator: slack-coordinator
    role: define|execute
  ```

## 2. Approach

```
/slack-collab "build auth system"
|
+- PHASE 0: PREFLIGHT (Lead alone, no team yet)
|  +- Preflight: ToolSearch for TeamCreate + SendMessage. Abort if missing.
|  +- Ask user via AskUserQuestion:
|  |   - Existing Slack channel ID (no creation)
|  |   - Stakeholders (names, Slack handles, roles, GitHub usernames)
|  |   - QA needs
|  +- TeamCreate(team_name: run_id) — must succeed before spawning
|  +- Spawn teammates (all with team_name): slack-coord (sonnet), define-worker, executor
|  +- Message slack-coord with kickoff context (not verbatim text)
|  +- Coord sends thread_ts values to lead
|  +- Lead writes state file
|
+- PHASE 1: DEFINE
|  +- Lead messages define-worker: "Run /define for [task]
|  |   TEAM_CONTEXT: lead: <name>, coordinator: slack-coordinator, role: define"
|  +- define-worker runs /define, messages lead for Q&A
|  +- Lead routes Q&A to coordinator -> Slack -> poll -> relay back
|  +- define-worker requests manifest-verifier -> lead spawns subagent
|  +- Subagent sends results directly to define-worker (or file fallback)
|  +- define-worker completes, messages lead: manifest_path
|  +- Lead writes state file
|
+- PHASE 2: MANIFEST REVIEW
|  +- Lead messages coord: "Post manifest for review, poll for approval"
|  +- If feedback: lead -> define-worker revises -> re-enter Phase 2
|  +- If approved: proceed
|  +- Lead writes state file
|
+- PHASE 3: EXECUTE
|  +- Lead messages executor: "Run /do for [manifest_path]
|  |   TEAM_CONTEXT: lead: <name>, coordinator: slack-coordinator, role: execute"
|  +- executor runs /do (MUST invoke via Skill tool), messages lead for escalations
|  +- executor runs /verify locally (inherits all tools from lead)
|  +- executor completes, messages lead
|  +- Lead writes state file
|
+- PHASE 4: PR + REVIEW
|  +- Lead messages executor: "Create PR"
|  +- Executor creates PR, messages lead with URL
|  +- Lead spawns github-coordinator (sonnet) with PR URL + reviewer GH handles
|  +- GitHub review request: coordinator adds reviewers (gh pr edit --add-reviewer) + initial comment
|  +- Slack notification: coordinator posts one message tagging reviewers, directing to GitHub
|  +- github-coordinator polls PR: reports diffs (bot/human labeled)
|  +- Bot comments -> define-worker classifies -> fix or FP (comment + resolve)
|  +- Human comments -> define-worker classifies -> comment -> wait approval -> resolve
|  +- Define-worker can amend manifest for valid gaps (INV-G*.* format)
|  +- CI failures -> compare base branch -> transient: empty commit -> new: executor fixes
|  +- ALL PR issues route through define-worker for AC eval BEFORE executor
|  +- Lead writes state file
|
+- PHASE 5: QA (optional, if QA stakeholders exist)
|  +- Lead messages coord: "Post QA request"
|  +- QA tester (human) posts issues in Slack thread
|  +- Coord picks up -> lead -> define-worker evaluates against manifest
|  +- Lead -> executor fixes validated issues
|  +- Repeat until QA sign-off or max 3 fix rounds then escalate
|  +- Lead writes state file
|
+- PHASE 6: DONE
   +- Lead messages coord: "Post completion summary" (tag all)
   +- Lead sends shutdown_request to all teammates
   +- Lead waits for shutdown confirmations
   +- Lead writes final state, tells user workflow complete
```

- **Risk Areas:**
  - [R-1] Subagent SendMessage feasibility — subagents spawned with team_name may not have SendMessage access | Detect: test on first launch; fall back to file-based handoff
  - [R-2] Mid-phase resume after long pause — /tmp files may not survive system restarts | Detect: document as known limitation
  - [R-3] Hub-and-spoke bottleneck — QA feedback loop has many hops | Detect: if >5 messages per QA issue, consider relaxing for future iteration
  - [R-4] State file write contention — mitigated by single-writer (lead) pattern
  - [R-5] Context overflow in lead from subagent relay — mitigated by subagent-direct-messaging + memento log
  - [R-6] Agent Teams experimental instability — teammate creation or messaging may fail | Detect: visible stall; lead re-spawns once then stops
  - [R-7] Teammates don't persist across phases — define-worker may be cleaned up before QA | Detect: lead monitors; re-spawns with manifest context if needed
  - [R-8] Lean polling breaks thread tracking — coordinator misses messages because last_seen_ts is wrong or stale | Detect: test with concurrent thread replies during a poll cycle
  - [R-9] Redundant guards create conflicting rules — SKILL.md says one thing, agent says slightly different | Detect: prompt-reviewer subagent catches conflicts (INV-G20)
  - [R-10] Define-worker manifest amendments during Phase 4 create confusion — executor works on outdated ACs | Detect: amendment protocol requires lead approval before executor acts
  - [R-11] Lead spawns regular subagents instead of teammates (missing TeamCreate/team_name) | Detect: preflight ToolSearch + explicit TeamCreate step + Never Do guard
  - [R-12] Slack-coordinator exits after completing a discrete lead request (context rot → "task done") | Detect: CRITICAL infinite loop callout + resume-after-handling reinforcement + What You Do NOT Do entry
  - [R-13] PR URLs not clickable in Slack (wrong formatting) | Detect: URL formatting guidance in slack-coordinator

- **Trade-offs:**
  - [T-1] Hub-and-spoke vs mesh -> Prefer hub-and-spoke: lead visibility, reduced teammate confusion
  - [T-2] Subagent-direct-messaging vs lead-relay -> Prefer direct: saves lead context; file fallback if infeasible
  - [T-3] Topic-based vs per-stakeholder threads -> Prefer topic-based: groups context by question
  - [T-4] 24h timeout vs shorter -> Prefer 24h: cross-timezone, business day workflows
  - [T-5] Dedicated coordinator vs lead-handles-Slack -> Prefer dedicated: clean separation of concerns
  - [T-6] Persistent define-worker vs fresh reviewer -> Prefer persistent: preserves full interview context for QA
  - [T-7] Brevity vs explicit guidance -> Prefer explicit for bot/human/CI rules (new behavior needs clarity) but keep existing sections concise
  - [T-8] Flexibility vs specificity -> Hard process rules (bot=resolve, human=discuss), flexible evaluation (define-worker judges merit)
  - [T-9] Self-contained coordinators vs lead-driven polling -> Prefer self-contained (proven pattern, simpler recovery) over CronCreate (moves context problem to lead)
  - [T-10] Consistency vs minimal change in lead message composition -> Prefer consistency: ALL lead-to-coordinator messages use context+instructions, not just new ones
  - [T-11] Polling reinforcement level: slack-coordinator vs github-coordinator -> Slack gets more (CRITICAL + inline + Do NOT Do) because it handles more discrete tasks with more exit signals; GitHub gets less (CRITICAL + Do NOT Do)

## 3. Global Invariants (The Constitution)

- [INV-G1] Standalone /define unchanged — /define without TEAM_CONTEXT behaves identically. COLLABORATION_MODE.md only activates with TEAM_CONTEXT block.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read claude-plugins/manifest-dev/skills/define/SKILL.md and claude-plugins/manifest-dev/skills/define/references/COLLABORATION_MODE.md. Verify COLLABORATION_MODE.md only activates when TEAM_CONTEXT block is present in $ARGUMENTS. Verify all non-collaboration paths are identical: AskUserQuestion, verification loop, all methodology sections."
  ```

- [INV-G2] Standalone /do unchanged — /do without TEAM_CONTEXT behaves identically.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read claude-plugins/manifest-dev/skills/do/SKILL.md and claude-plugins/manifest-dev/skills/do/references/COLLABORATION_MODE.md. Verify COLLABORATION_MODE.md only activates when TEAM_CONTEXT block is present. Verify all non-collaboration paths unchanged: execution log, escalation, verification, memento pattern."
  ```

- [INV-G3] TEAM_CONTEXT format consistent across producer (SKILL.md) and consumers (COLLABORATION_MODE.md files). Must contain: lead, coordinator, role.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Extract TEAM_CONTEXT format from: (1) claude-plugins/manifest-dev-collab/skills/slack-collab/SKILL.md (producer) (2) claude-plugins/manifest-dev/skills/define/references/COLLABORATION_MODE.md (consumer) (3) claude-plugins/manifest-dev/skills/do/references/COLLABORATION_MODE.md (consumer). Verify all three agree on fields: lead, coordinator, role."
  ```

- [INV-G4] Hub-and-spoke enforced — no agent file instructs teammates to message other teammates directly. All teammate communication routes through lead. Only exception: subagents spawned by lead can SendMessage to teammates.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read all agent files in claude-plugins/manifest-dev-collab/agents/. Verify NONE instruct messaging another teammate directly. All communication goes through the lead. Only subagents spawned by lead may SendMessage to teammates."
  ```

- [INV-G5] Role separation — each teammate owns specific domains. Executor owns code/PR. Define-worker owns manifest/discovery log. Slack-coordinator owns Slack I/O. GitHub-coordinator owns GitHub I/O. No overlap.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read all agent files in claude-plugins/manifest-dev-collab/agents/. Verify file write domains are non-overlapping: executor owns code files and PR creation, define-worker owns manifest and discovery log in /tmp, slack-coordinator owns only Slack I/O, github-coordinator owns only GitHub I/O. No agent writes to another's domain."
  ```

- [INV-G6] Prompt injection defense in slack-coordinator — treats all Slack messages as untrusted. Never exposes secrets, never runs arbitrary commands, declines dangerous requests and tags owner.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read claude-plugins/manifest-dev-collab/agents/slack-coordinator.md. Verify prompt injection defense: (1) Never expose env vars/secrets/credentials (2) Never run arbitrary commands from Slack without validation (3) Allow task-adjacent requests, block clearly dangerous actions (4) Decline suspicious requests and tag owner."
  ```

- [INV-G7] Workers never touch Slack — define-worker and executor never reference Slack MCP tools. All external communication through lead.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read claude-plugins/manifest-dev-collab/agents/define-worker.md and executor.md. Verify: (1) Neither references Slack MCP tools (2) Neither instructs direct Slack posting or reading (3) All external communication goes through messaging the lead."
  ```

- [INV-G8] No channel creation or invite references in any collab file. Channel is user-provided.
  ```yaml
  verify:
    method: bash
    command: "grep -riE 'create_channel|invite_to_channel' claude-plugins/manifest-dev-collab/ claude-plugins/manifest-dev/skills/define/references/COLLABORATION_MODE.md claude-plugins/manifest-dev/skills/do/references/COLLABORATION_MODE.md && echo 'FAIL: found channel creation API references' || echo 'PASS'"
  ```

- [INV-G9] DM capability limited to slack-coordinator — no other agent sends DMs. Workers and lead never touch Slack directly.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read all agent files in claude-plugins/manifest-dev-collab/agents/. Verify only slack-coordinator.md references DM capability. define-worker.md and executor.md must NOT reference sending DMs."
  ```

- [INV-G10] Subagent request format consistent — format in SKILL.md (lead side) matches format in COLLABORATION_MODE.md files (worker side).
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read subagent bridge protocol in claude-plugins/manifest-dev-collab/skills/slack-collab/SKILL.md and both COLLABORATION_MODE.md files. Verify the subagent request format is consistent across all three — same fields, same structure."
  ```

- [INV-G11] Kebab-case naming on all files.
  ```yaml
  verify:
    method: bash
    command: "find claude-plugins/manifest-dev-collab -type f | grep -v '.claude-plugin' | grep -v __pycache__ | grep -v README.md | grep -v SKILL.md | while read f; do basename \"$f\" | grep -qE '^[a-z0-9][a-z0-9_-]*\\.[a-z]+$' || echo \"FAIL: $f\"; done"
  ```

- [INV-G12] Valid plugin JSON with required fields.
  ```yaml
  verify:
    method: bash
    command: "python3 -c \"import json; d=json.load(open('claude-plugins/manifest-dev-collab/.claude-plugin/plugin.json')); assert all(k in d for k in ['name','version','description']), f'Missing fields: {d.keys()}'; print('PASS')\""
  ```

- [INV-G13] Skill frontmatter valid — name (kebab-case, max 64), description (max 1024, action-oriented).
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read claude-plugins/manifest-dev-collab/skills/slack-collab/SKILL.md. Verify YAML frontmatter has: name (kebab-case, max 64 chars), description (max 1024 chars, action-oriented). Verify user-invocable is true or defaulted."
  ```

- [INV-G14] Prompt quality — no prescriptive HOW, no arbitrary limits, no capability instructions, no weak language, no buried critical info. All prompts state goals and constraints.
  ```yaml
  verify:
    method: subagent
    agent: prompt-reviewer
    model: opus
    prompt: "Review all prompt files in claude-plugins/manifest-dev-collab/ (SKILL.md and all agents) and both COLLABORATION_MODE.md files for anti-patterns: prescriptive HOW, arbitrary limits, capability instructions, weak language, buried critical info, over-engineering, contradictions, ambiguity. Also check: domain context accuracy, complexity fit, description quality, guardrail calibration."
  ```

- [INV-G15] Documentation accurate — READMEs reflect current architecture: 60s lean polling, bot/human triage, CI triage, lead orchestrator role, define-worker Phase 4 amendments, state file recovery, pronoun disambiguation, identity transparency.
  ```yaml
  verify:
    method: subagent
    agent: docs-reviewer
    model: opus
    prompt: "Compare README.md files (root, claude-plugins/, manifest-dev-collab/, manifest-dev/) with actual agent and skill files. Verify READMEs accurately describe: user provides channel, hub-and-spoke communication, subagent bridge (executor self-verifies), 60s split-sleep lean polling, DM capability, 24h timeout, topic-based threads, sonnet coordinators, github-coordinator, bot/human PR comment triage, CI failure triage, lead orchestrator role, define-worker Phase 4 amendments, state file recovery. No stale references to Python orchestrator, COLLAB_CONTEXT, session-resume, channel creation, haiku model, or 30s polling."
  ```

- [INV-G16] CLAUDE.md adherence — kebab-case, version bumps, README sync, frontmatter conventions.
  ```yaml
  verify:
    method: subagent
    agent: claude-md-adherence-reviewer
    model: opus
    prompt: "Review all files in claude-plugins/manifest-dev-collab/ and the two COLLABORATION_MODE.md files against project CLAUDE.md. Check: kebab-case naming, plugin versions consistent, README sync checklist, skill/agent frontmatter format."
  ```

- [INV-G17] Python orchestrator fully removed — no orphan files.
  ```yaml
  verify:
    method: bash
    command: "test ! -f claude-plugins/manifest-dev-collab/scripts/slack-collab-orchestrator.py && test ! -d tests/collab && echo PASS || echo FAIL"
  ```

- [INV-G18] No stale V1/V2 references in any file.
  ```yaml
  verify:
    method: bash
    command: "if grep -rli 'COLLAB_CONTEXT\\|slack-collab-orchestrator\\.py\\|session-resume\\|session_resume' claude-plugins/manifest-dev-collab/ claude-plugins/manifest-dev/skills/define/references/COLLABORATION_MODE.md claude-plugins/manifest-dev/skills/do/references/COLLABORATION_MODE.md 2>/dev/null; then echo FAIL; else echo PASS; fi"
  ```

- [INV-G19] No ambiguous instructions — every instruction in all prompt files has exactly one valid interpretation.
  ```yaml
  verify:
    method: subagent
    agent: prompt-reviewer
    prompt: "Review these 5 prompt files for clarity issues (ambiguous instructions, vague language, implicit expectations): slack-collab/SKILL.md, slack-coordinator.md, github-coordinator.md, executor.md, define-worker.md"
  ```

- [INV-G20] No conflicting rules — no contradictory instructions within or across files, especially between SKILL.md orchestration rules and agent-level redundant guards.
  ```yaml
  verify:
    method: subagent
    agent: prompt-reviewer
    prompt: "Check these 5 files for conflicting rules, priority collisions, and edge case gaps. Pay special attention to redundant guard rules that appear in both SKILL.md and agent files — they must be consistent: slack-collab/SKILL.md, slack-coordinator.md, github-coordinator.md, executor.md, define-worker.md"
  ```

- [INV-G21] Critical rules surfaced prominently — compliance-critical instructions (Phase 4 routing, shutdown, bot/human process) are not buried in middle paragraphs.
  ```yaml
  verify:
    method: subagent
    prompt: "For each of these 5 files, identify the 3 most critical behavioral rules. Verify each is in a prominent position (section header, bold text, or first paragraph of its section) — not buried in the middle of a long paragraph: slack-collab/SKILL.md, slack-coordinator.md, github-coordinator.md, executor.md, define-worker.md"
  ```

- [INV-G22] Information density — no filler, no redundant explanations, every sentence earns its place. Files should not grow significantly in line count despite adding new features.
  ```yaml
  verify:
    method: subagent
    agent: prompt-token-efficiency-verifier
    prompt: "Analyze these 5 files for token efficiency. Flag redundant content, verbose explanations, and sentences that add no behavioral constraint: slack-collab/SKILL.md, slack-coordinator.md, github-coordinator.md, executor.md, define-worker.md"
  ```

- [INV-G23] No anti-patterns — no prescriptive HOW (step-by-step scripts), no arbitrary limits, no capability instructions ("use grep"), no weak language ("try to", "maybe").
  ```yaml
  verify:
    method: subagent
    agent: prompt-reviewer
    prompt: "Scan these 5 files for prompt anti-patterns: prescriptive HOW language, arbitrary numeric limits, capability instructions, weak language. Report all instances: slack-collab/SKILL.md, slack-coordinator.md, github-coordinator.md, executor.md, define-worker.md"
  ```

- [INV-G24] Existing security sections preserved — untrusted input handling, prompt injection defense sections in both coordinators must remain intact and functionally equivalent.
  ```yaml
  verify:
    method: subagent
    prompt: "Use git show HEAD:path to get the original versions. Compare the Security sections in the updated slack-coordinator.md and github-coordinator.md against their git HEAD versions. Verify all security rules are preserved (untrusted input handling, prompt injection defense, credential protection). Report any weakened or removed security rules."
  ```

- [INV-G25] All current coordinator capabilities preserved — thread tracking, stakeholder routing, proactive reporting, owner override, DM support, long content splitting, PR completion criteria — nothing lost in updates.
  ```yaml
  verify:
    method: subagent
    prompt: "Use git show HEAD:path to get the original versions. For each coordinator file (slack-coordinator.md, github-coordinator.md), list every capability documented in the git HEAD version. Verify each capability is still present in the updated version. Report any capability that was removed or weakened."
  ```

- [INV-G26] Coordinator pronoun disambiguation — when relaying messages between stakeholders and the team, coordinators replace ambiguous pronouns ("you", "me", "us") with specific names/roles to prevent misattribution.
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-coordinator.md and github-coordinator.md. Verify both contain instructions to disambiguate pronouns when relaying messages (replace ambiguous 'you'/'me'/'us' with specific names or roles)."
  ```

- [INV-G27] Lead identity transparency — if stakeholders ask about the identity of unnamed analysis contributions, the coordinator responds honestly (AI orchestrator providing analysis). Only when directly asked, never volunteered.
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-coordinator.md. Verify it contains guidance on responding to identity questions about the lead's contributions: transparent when asked, AI orchestrator identity, not volunteered proactively."
  ```

## 4. Process Guidance (Non-Verifiable)

- [PG-1] Use `/prompt-engineering` skill for all prompt changes — skill/agent files are LLM prompts.
- [PG-2] Right-sized changes — each update addresses only what's specified. No scope creep. One edge case doesn't warrant restructuring the entire file.
- [PG-3] Agent definitions should be self-contained — each has everything the teammate needs. Don't assume it reads the skill.
- [PG-4] TEAM_CONTEXT must stay minimal. New fields require manifest amendment.
- [PG-5] State file schema should be flat and simple — no nested schemas beyond stakeholder list and phase_state. New fields (last_seen_ts, reaction tracking) are additive — extend, don't replace.
- [PG-6] State file single-writer — lead owns all writes. Coordinator sends thread updates via message; lead writes them.
- [PG-7] Launch verification subagents in parallel — use `run_in_background`.
- [PG-8] Test subagent SendMessage feasibility on first launch. If fails, switch to file-based handoff for all subsequent.
- [PG-9] Guard against scope creep — no Slack notifications beyond Q&A, reviews, escalations, completion. No progress posts.
- [PG-10] Lead memento pattern: re-read state file after each phase transition. Log subagent interactions to `/tmp/collab-subagent-log-{run_id}.md`.
- [PG-11] Document load-bearing assumptions in each changed file.
- [PG-12] When adding redundant guards to agent files, mirror the SKILL.md rule's intent but phrase it from the agent's perspective (what the agent should do when it detects the violation, not what the lead should do).
- [PG-13] When updating the event loop section, preserve the existing split-sleep pattern for lead message responsiveness — coordinators must check for lead messages between sleep halves so they remain interruptible.
- [PG-14] Use the prompt-engineering skill's principles when crafting new sections — state WHAT and WHY, not HOW. Trust model capability.

## 5. Known Assumptions

- [ASM-1] `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` is set | Impact if wrong: team creation fails
- [ASM-2] /tmp files persist within session | Impact if wrong: resume fails
- [ASM-3] Teammates inherit Slack MCP from project context | Impact if wrong: coordinator can't use Slack
- [ASM-4] /define and /do invoked via Skill tool inside teammates work normally | Impact if wrong: workers follow methodology from agent prompt instead
- [ASM-5] One lead can manage 4 teammates simultaneously (slack-coord, github-coord, define-worker, executor) | Impact if wrong: reduce to 3 (merge coordinator roles)
- [ASM-6] Agent frontmatter omits tools: — agents inherit all tools from lead context | Impact if wrong: agents may lack needed tools
- [ASM-7] Slack API supports reading reactions via the existing MCP tools (slack_read_thread returns reaction data) | Default: Yes | Impact if wrong: reaction monitoring would need a different MCP tool or API call
- [ASM-8] GitHub PR thread resolution is possible via `gh` CLI or GitHub MCP tools available to the github-coordinator | Default: Yes | Impact if wrong: bot thread resolution would need a manual workflow instead
- [ASM-9] Define-worker can amend the manifest file directly during Phase 4 (write access to /tmp/manifest-*.md) | Default: Yes, define-worker already writes to /tmp/ | Impact if wrong: amendments would need to go through the lead as file-based handoff
- [ASM-10] Slack-coordinator exit-after-discrete-task problem is caused by missing prompt reinforcement, not deeper architectural issue | Default: prompt reinforcement sufficient (github-coordinator stays alive better with same rule but fewer discrete tasks) | Impact if wrong: needs external keepalive mechanism
- [ASM-11] GitHub handles provided by users are valid GitHub usernames | Default: gh pr edit --add-reviewer fails gracefully for invalid handles | Impact if wrong: reviewer assignment silently fails for that user

## 6. Deliverables (The Work)

### Deliverable 1: Lead Orchestrator — SKILL.md
*File: `claude-plugins/manifest-dev-collab/skills/slack-collab/SKILL.md`*

- [AC-1.1] Phase 0 asks user for existing Slack channel ID via AskUserQuestion (no channel creation). Documents that stakeholders must already be in the channel.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read claude-plugins/manifest-dev-collab/skills/slack-collab/SKILL.md. Verify Phase 0 asks user for existing channel ID (not creating a channel). Verify it documents stakeholders must already be in channel."
  ```

- [AC-1.2] Phase 0 gathers stakeholders (names, handles, roles, QA flags) via AskUserQuestion. Passes full roster to coordinator at spawn time.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read SKILL.md. Verify preflight gathers stakeholder info and passes the full roster to slack-coordinator in its spawn prompt as a routing table."
  ```

- [AC-1.3] Creates team with 3 teammates via `subagent_type` identifiers (manifest-dev-collab:slack-coordinator, manifest-dev-collab:define-worker, manifest-dev-collab:executor). Coordinator spawned with model: sonnet. Define-worker and executor omit model (inherits parent). github-coordinator spawned in Phase 4 with model: sonnet.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read SKILL.md. Verify team creation spawns 3 teammates in Phase 0 via subagent_type identifiers (manifest-dev-collab:*). Verify slack-coordinator specifies model: sonnet. Verify define-worker and executor omit model (inherits parent). Verify github-coordinator spawned in Phase 4 with model: sonnet."
  ```

- [AC-1.4] Hub-and-spoke communication model explicitly stated. Teammates only message lead.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read SKILL.md. Verify it explicitly states hub-and-spoke: teammates only communicate with lead. No direct teammate-to-teammate messaging."
  ```

- [AC-1.5] Subagent bridge protocol documented with concrete request format including: what subagent to run, prompt, who receives results, context files.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read SKILL.md. Verify subagent bridge protocol: worker request format, lead spawn mechanism, result delivery (SendMessage primary, file-based fallback with naming convention /tmp/subagent-result-{run_id}-{request_id}.md), how lead logs interactions."
  ```

- [AC-1.6] Subagent SendMessage feasibility test: lead tests on first subagent launch, falls back to file-based if fails.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read SKILL.md. Verify it instructs testing subagent SendMessage feasibility on first launch and falling back to file-based handoff if it fails."
  ```

- [AC-1.7] Phase flow: preflight -> define -> manifest review -> execute -> PR -> QA (optional) -> done. Each phase described with lead's specific actions.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read SKILL.md. Verify 7 phases in order: (0) Preflight (1) Define (2) Manifest Review (3) Execute (4) PR (5) QA optional (6) Done. Verify lead's actions per phase match the architecture."
  ```

- [AC-1.8] Phase 5 (QA) routes through lead: coordinator -> lead -> define-worker evaluates -> lead -> executor fixes. No direct define-worker-to-executor messaging.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read SKILL.md Phase 5. Verify QA flow: coordinator -> lead -> define-worker -> lead -> executor. No direct define-worker-to-executor messaging."
  ```

- [AC-1.9] State file written after every phase transition. Schema includes: run_id, phase, channel_id, stakeholders, threads (with per-thread `last_seen_ts`), manifest_path, pr_url, phase_state (active threads, polling status for mid-phase resume). Schema is additive — extends existing JSON, doesn't replace it.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read SKILL.md. Verify state file written after each phase transition with schema including phase_state for mid-phase resume and per-thread last_seen_ts for diff polling recovery. Lead is single writer."
  ```

- [AC-1.10] Resume capability: `--resume <state-file-path>` reads state, re-creates team, continues from interrupted phase. Supports mid-phase resume for polling states.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read SKILL.md. Verify resume reads state file, re-creates team with existing context, continues from interrupted phase including mid-phase polling states."
  ```

- [AC-1.11] Teammate crash handling: re-spawn once with same task. Second failure: write state, stop.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read SKILL.md. Verify: on teammate failure, re-spawn once. On second failure, write state and inform user. No infinite retry."
  ```

- [AC-1.12] Lead memento: subagent interaction log at `/tmp/collab-subagent-log-{run_id}.md`. Re-read state file before phase transitions.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read SKILL.md. Verify lead memento pattern: subagent interaction log file, re-read state file before phase transitions."
  ```

- [AC-1.13] TEAM_CONTEXT format includes `lead` field with lead's name, coordinator field, and role field.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read SKILL.md. Verify TEAM_CONTEXT format includes lead field with lead's name, coordinator field, and role field."
  ```

- [AC-1.14] State file write ownership documented: lead is single writer. Coordinator sends thread updates via message.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read SKILL.md. Verify state file is lead-owned for writes. Coordinator sends thread tracking updates via message to lead."
  ```

- [AC-1.15] Prerequisites list only actually available Slack MCP tools. No create_channel or invite_to_channel.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read SKILL.md Prerequisites. Verify it lists only available Slack MCP tools (send_message, read_channel, read_thread, search_channels, search_users, read_user_profile). No create_channel or invite_to_channel."
  ```

- [AC-1.16] No references to channel creation, invite_to_channel, COLLAB_CONTEXT, or Python orchestrator. (DMs are now supported via slack-coordinator.)
  ```yaml
  verify:
    method: bash
    command: "grep -iE 'create.channel|invite.channel|COLLAB_CONTEXT|orchestrator\\.py' claude-plugins/manifest-dev-collab/skills/slack-collab/SKILL.md && echo 'FAIL' || echo 'PASS'"
  ```

- [AC-1.17] "User Communication After Phase 0" section: all user comms through slack-coordinator, not terminal. Only exception: coordinator failure escalation.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read SKILL.md. Verify a section stating all user communication after Phase 0 goes through slack-coordinator. No terminal output or AskUserQuestion during workflow. Only exception: coordinator failure escalation."
  ```

- [AC-1.18] Subagent Bridge Protocol notes executor self-verifies (runs /verify locally). Bridge applies to define-worker and non-verification subagent needs only.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read SKILL.md Subagent Bridge Protocol. Verify it notes executor runs /verify locally (not through bridge). Bridge applies to define-worker's manifest-verifier and other non-verification needs."
  ```

- [AC-1.19] Phase 4 section includes **bot vs human PR comment triage rules**: Bot threads -> define-worker classifies -> fix or mark FP (comment for visibility + resolve). Human threads -> define-worker classifies -> comment response + wait for approval -> only resolve after human approves.
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-collab/SKILL.md Phase 4 section. Verify it contains explicit rules for: (1) bot comment handling (classify -> fix or FP -> resolve without discussion), (2) human comment handling (classify -> comment -> wait for approval -> resolve only after approval), (3) FP visibility commenting before resolution."
  ```

- [AC-1.20] Phase 4 section includes **CI failure triage**: Compare against base branch CI -> transient failures get empty commit retrigger -> only genuinely new failures routed to executor.
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-collab/SKILL.md Phase 4 section. Verify it contains: (1) instruction to compare CI failures against base branch, (2) transient failure handling (empty commit to retrigger), (3) only new failures routed to executor."
  ```

- [AC-1.21] **Lead orchestrator identity** defined: Lead can contribute to discussions (answer when referenced, weigh in with insights, surface conflicts, fact-check claims). Unnamed voice (no system attribution prefix). Role hierarchy: lead = orchestrator, humans = advisors, owner = override power.
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-collab/SKILL.md. Verify it defines the lead's orchestrator role: (1) lead CAN contribute to Slack discussions through coordinator, (2) contributions are unnamed (no system attribution), (3) role hierarchy stated (orchestrator/advisors/owner override), (4) specific contribution types listed."
  ```

- [AC-1.22] **Phase 4 PR comment routing mandate** strengthened: ALL PR review issues MUST route through define-worker for AC evaluation before reaching executor. Uses CRITICAL/MUST/NEVER language. This is a redundant guard — also appears in executor.md (AC-4.7).
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-collab/SKILL.md Phase 4 section. Verify it contains an explicit, prominently-placed rule that ALL PR review issues must route through define-worker for AC evaluation before reaching executor. The rule should use strong compliance language (CRITICAL, MUST, NEVER). Confirm this rule cannot be missed when reading the Phase 4 section."
  ```

- [AC-1.23] **Define-worker Phase 4 manifest amendment** workflow documented: Define-worker receives unresolved comments -> evaluates on merit -> amends manifest with new ACs/INVs for valid ones -> explains dropped ones with reasoning -> lead approves amendments -> executor implements. Amendment protocol (INV-G*.* format) used.
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-collab/SKILL.md Phase 4 section. Verify it documents: (1) define-worker can amend manifest during Phase 4, (2) amendment workflow (classify -> amend -> explain drops -> lead approve -> executor implement), (3) uses standard amendment protocol (INV-G*.* format)."
  ```

- [AC-1.24] **Manifest amendment message format** defined: When define-worker sends amendments through the lead to executor, uses a structured format (MANIFEST_AMENDMENT with ID, description, verify method). Analogous to existing SUBAGENT_REQUEST and VERIFICATION_REQUEST formats.
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-collab/SKILL.md Phase 4 section. Verify it defines a structured message format for manifest amendments flowing from define-worker through lead to executor. The format should include amendment ID, description, and verification method — similar to SUBAGENT_REQUEST format."
  ```

- [AC-1.25] **Coordinator polling model** section: 60-second interval, lean diff-only reporting, state file recovery on compaction. Coordinators remain interruptible (check for lead messages between sleep halves).
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-collab/SKILL.md sections about coordinators. Verify: (1) 60-second polling interval mentioned, (2) diff-only reporting described, (3) state file recovery on compaction documented, (4) coordinators described as interruptible (responsive to lead messages during polling)."
  ```

### Deliverable 2: Slack Coordinator Agent
*File: `claude-plugins/manifest-dev-collab/agents/slack-coordinator.md`*

- [AC-2.1] Channel setup responsibility: receives channel_id from lead (user-provided). No channel creation.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read slack-coordinator.md. Verify channel creation NOT listed as responsibility. Expects channel_id from lead."
  ```

- [AC-2.2] **Lean polling model**: Event loop uses `last_seen_ts` per thread — only reads new messages after that timestamp. Reports diffs only (new replies, not full thread content). 60-second total interval (two 30-second sleep halves for lead message responsiveness). Never stops on its own. Never increases the interval. Checks for lead messages at least 3 times per cycle (before polling, after polling, mid-sleep).
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read slack-coordinator.md. Verify: (1) polling uses last_seen_ts to read only new messages (2) reports diffs only, no full thread re-reads (3) 60-second split-sleep cycle (two 30s halves with mailbox check between) (4) never stops on its own (5) never increases the interval (6) checks for lead messages at least 3 times per cycle."
  ```

- [AC-2.3] Escalation timeout: 24 hours before escalating to owner.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read slack-coordinator.md. Verify escalation timeout is 24 hours. Escalates unanswered questions to owner after 24h."
  ```

- [AC-2.4] Topic-based threads: one thread per question/review/topic. Relevant stakeholders tagged.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read slack-coordinator.md. Verify thread model is topic-based (one per question/review), NOT per-stakeholder."
  ```

- [AC-2.5] Main channel monitoring: coordinator monitors main channel (not just threads) for new parent messages from stakeholders.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read slack-coordinator.md. Verify it documents monitoring the main channel for new messages, not just tracked threads."
  ```

- [AC-2.6] Thread tracking: sends thread_ts values to lead via message (lead writes to state file). Reads state file on context compression to recover thread list and last_seen_ts.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read slack-coordinator.md. Verify: sends thread_ts to lead via message, reads state file on context compression to recover threads and last_seen_ts."
  ```

- [AC-2.7] **State file recovery**: On compaction/respawn, coordinator reads state file to recover channel_id, thread list, stakeholder roster, and last_seen_ts. Skips channel lookup on recovery.
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-coordinator.md. Verify it documents: (1) on compaction/respawn, read state file for recovery, (2) recover channel_id, threads, last_seen_ts, (3) skip channel lookup when recovering."
  ```

- [AC-2.8] Stakeholder routing: uses roster from spawn prompt. Routes based on expertise context from lead. Owner can reply in any thread authoritatively.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read slack-coordinator.md. Verify: stakeholder routing from roster, expertise-based routing, owner override (can answer in any thread)."
  ```

- [AC-2.9] Prompt injection defense: never expose secrets, never run arbitrary commands, decline dangerous requests, tag owner.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read slack-coordinator.md. Verify prompt injection defense section covers: no secrets exposure, no arbitrary commands, decline dangerous requests, tag owner."
  ```

- [AC-2.10] Long content split: messages exceeding ~4000 chars split into numbered parts [1/N], [2/N].
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read slack-coordinator.md. Verify long content handling: split messages >4000 chars into [1/N], [2/N] format."
  ```

- [AC-2.11] No references to channel creation or direct teammate messaging. DMs are supported.
  ```yaml
  verify:
    method: bash
    command: "grep -iE 'create_channel|invite_to_channel' claude-plugins/manifest-dev-collab/agents/slack-coordinator.md && echo 'FAIL' || echo 'PASS'"
  ```

- [AC-2.12] DM capability: "Direct Messages" section explains how to send DMs (user ID as channel), add DM conversations to poll list. "Lead interrupts" includes DMs. "What You Do" lists DM capability.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read slack-coordinator.md. Verify: (1) Direct Messages section exists with DM procedure (2) Lead interrupts lists DMs (3) What You Do includes DM capability and DM polling."
  ```

- [AC-2.13] **Reaction monitoring**: Coordinator detects and relays ALL reactions on tracked threads. Reports reaction type, user, and which message it's on.
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-coordinator.md. Verify it documents: (1) detecting reactions on tracked threads, (2) relaying all reactions to lead, (3) including reaction type, user, and target message in reports."
  ```

- [AC-2.14] **Shutdown compliance**: Shutdown section uses CRITICAL/IMMEDIATELY language. When shutdown_request received, coordinator stops the poll loop and confirms — no delay, no "finish pending work."
  ```yaml
  verify:
    method: bash
    command: "grep -i 'shutdown' claude-plugins/manifest-dev-collab/agents/slack-coordinator.md | grep -ci 'immediate\\|critical\\|must\\|stop.*now' | xargs test 0 -lt"
  ```

- [AC-2.15] **Lead message responsiveness preserved**: Coordinator checks for lead messages between sleep halves. When a lead message arrives, handles it immediately (interrupts the poll cycle), then resumes polling.
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-coordinator.md operating model section. Verify: (1) coordinator checks for lead messages between sleep halves, (2) lead messages are handled immediately (interrupt polling), (3) polling resumes after handling."
  ```

- [AC-2.16] **Pronoun disambiguation**: When relaying stakeholder messages, coordinator replaces ambiguous pronouns ("you", "me", "us") with specific names/roles to prevent misattribution.
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-coordinator.md. Verify it contains instructions to disambiguate pronouns when relaying messages between stakeholders and the team."
  ```

- [AC-2.17] **Lead identity transparency**: When stakeholders ask about unnamed analysis contributions, coordinator responds honestly (AI orchestrator) but only when directly asked.
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-coordinator.md. Verify it contains guidance for responding to stakeholder questions about the identity of the lead's unnamed contributions."
  ```

### Deliverable 3: Define Worker Agent
*File: `claude-plugins/manifest-dev-collab/agents/define-worker.md`*

- [AC-3.1] Primary task: invoke /define with TEAM_CONTEXT. Messages lead for all communication.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read define-worker.md. Verify: invokes /define with TEAM_CONTEXT, messages lead (not coordinator or executor) for all communication."
  ```

- [AC-3.2] Verification delegation: messages lead for manifest-verifier with structured subagent request. Does not spawn subagents directly.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read define-worker.md. Verify: messages lead for manifest-verifier (not spawning directly). Request includes agent type, prompt, target files."
  ```

- [AC-3.3] Receives verification results from subagents (SendMessage) or from lead (file path fallback).
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read define-worker.md. Verify it handles receiving results via SendMessage from subagent OR via lead message with file path."
  ```

- [AC-3.4] Persists after /define as manifest authority. Evaluates QA issues against ACs.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read define-worker.md. Verify: stays alive after /define, evaluates QA issues against manifest ACs, identifies which ACs violated, provides fix guidance."
  ```

- [AC-3.5] Never touches Slack. No references to Slack MCP tools or direct teammate messaging.
  ```yaml
  verify:
    method: bash
    command: "grep -i 'message.*executor\\|message.*coordinator\\|send.*executor\\|send.*coordinator\\|slack_' claude-plugins/manifest-dev-collab/agents/define-worker.md | grep -vi 'NOT\\|never\\|Do not' && echo 'FAIL' || echo 'PASS'"
  ```

- [AC-3.6] **Phase 4 role documented**: Define-worker evaluates PR review comments during Phase 4 (not just QA in Phase 5). Classifies each comment as: actionable (fix instructions + AC refs), false-positive (reasoning), or needs-clarification.
  ```yaml
  verify:
    method: subagent
    prompt: "Read define-worker.md. Verify it documents a Phase 4 role: (1) evaluates PR review comments against manifest, (2) classifies as actionable/FP/needs-clarification, (3) provides fix instructions with AC references for actionable items."
  ```

- [AC-3.7] **Manifest amendment capability**: Define-worker can amend the manifest during Phase 4 when PR review reveals genuine gaps. Uses standard amendment protocol (INV-G*.*, AC-*.* format). Explains dropped comments with reasoning. Lead approves amendments.
  ```yaml
  verify:
    method: subagent
    prompt: "Read define-worker.md. Verify it documents: (1) manifest amendment capability during Phase 4, (2) standard amendment protocol, (3) dropped comments explained with reasoning, (4) lead approval required before amendments take effect."
  ```

- [AC-3.8] **Flexible evaluation**: Define-worker evaluates each comment on merit regardless of source (bot or human). Either side can be wrong. Evaluation considers project value, not source authority. Human reviewer resistance is considered but owner is final authority.
  ```yaml
  verify:
    method: subagent
    prompt: "Read define-worker.md. Verify it states: (1) evaluate comments on merit regardless of source, (2) either bots or humans can be wrong, (3) human resistance considered, (4) owner is final authority."
  ```

### Deliverable 4: Executor Agent
*File: `claude-plugins/manifest-dev-collab/agents/executor.md`*

- [AC-4.1] Primary task: invoke /do with TEAM_CONTEXT. Messages lead for all communication.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read executor.md. Verify: invokes /do with TEAM_CONTEXT, messages lead (not coordinator or define-worker) for all communication."
  ```

- [AC-4.2] Executor runs /verify locally (has all tools inherited from lead). MUST invoke /do via Skill tool — never implement directly. Contains WHY rationale (execution logs, hooks enforcement, /verify).
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read executor.md. Verify: (1) MUST language requiring /do invocation via Skill tool (2) Do NOT prohibition against direct implementation (3) WHY rationale covering execution logs, stop_do_hook enforcement, and /verify (4) 'Do NOT' section does NOT prohibit /verify or subagent spawning."
  ```

- [AC-4.3] QA issues received from lead (not define-worker directly).
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read executor.md. Verify QA issues come from lead, not define-worker directly."
  ```

- [AC-4.4] Runs /verify locally. Verification results are local to executor context.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read executor.md. Verify the executor runs /verify locally per COLLABORATION_MODE.md. No mention of receiving verification results from the lead."
  ```

- [AC-4.5] Creates PR, fixes review comments, fixes QA issues.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read executor.md. Verify: creates PR with gh, fixes review comments, fixes validated QA issues."
  ```

- [AC-4.6] Never touches Slack. No references to Slack MCP tools or direct teammate messaging.
  ```yaml
  verify:
    method: bash
    command: "grep -i 'message.*define.worker\\|message.*coordinator\\|send.*define.worker\\|send.*coordinator\\|slack_' claude-plugins/manifest-dev-collab/agents/executor.md | grep -vi 'NOT\\|never\\|Do not' && echo 'FAIL' || echo 'PASS'"
  ```

- [AC-4.7] **Redundant guard: Phase 4 PR issue routing**: Executor rejects PR review issues that arrive without AC references from the define-worker. If the lead sends review issues directly (without define-worker evaluation), executor messages lead: "These issues need AC evaluation from the define-worker first."
  ```yaml
  verify:
    method: subagent
    prompt: "Read executor.md Phase 4 section. Verify it contains a redundant guard: (1) executor checks that PR review issues include AC references from define-worker, (2) if missing, executor messages lead to route through define-worker first, (3) this is framed as the executor's responsibility, not just a SKILL.md rule."
  ```

- [AC-4.8] **CI triage awareness**: Executor knows to compare CI failures against base branch. When asked to fix CI issues, executor first checks if they exist on base branch. Pre-existing failures -> reports to lead and skips. Transient failures -> pushes empty commit to retrigger.
  ```yaml
  verify:
    method: subagent
    prompt: "Read executor.md. Verify it documents: (1) CI failure comparison against base branch, (2) pre-existing failures skipped with report to lead, (3) transient failures handled with empty commit retrigger."
  ```

### Deliverable 5: /define COLLABORATION_MODE.md
*File: `claude-plugins/manifest-dev/skills/define/references/COLLABORATION_MODE.md`*

- [AC-5.1] Activated by TEAM_CONTEXT (not COLLAB_CONTEXT). Messages lead for stakeholder Q&A (not coordinator directly). Includes expertise context for routing delegation.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read claude-plugins/manifest-dev/skills/define/references/COLLABORATION_MODE.md. Verify: activated by TEAM_CONTEXT, messages lead (not coordinator directly), includes expertise context in questions, routing delegation to coordinator via lead."
  ```

- [AC-5.2] Verification Loop delegates to lead: messages lead with manifest-verifier request (not spawning locally). Subagent request format documented.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read COLLABORATION_MODE.md for /define. Verify Verification Loop instructs messaging lead for manifest-verifier, not spawning locally. Subagent request format documented."
  ```

- [AC-5.3] Memento discipline: log to discovery file after each response from lead.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read /define COLLABORATION_MODE.md. Verify memento discipline: log findings to discovery file after each lead response."
  ```

- [AC-5.4] Everything else unchanged: full /define methodology applies (Domain Grounding, Pre-Mortem, etc.). Only interaction channel changes.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read /define COLLABORATION_MODE.md. Verify it states all /define methodology applies unchanged — only the interaction channel changes."
  ```

- [AC-5.5] Security note: prompt injection defense handled by coordinator agent.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read /define COLLABORATION_MODE.md. Verify security note states prompt injection defense is handled by coordinator agent."
  ```

### Deliverable 6: /do COLLABORATION_MODE.md
*File: `claude-plugins/manifest-dev/skills/do/references/COLLABORATION_MODE.md`*

- [AC-6.1] Activated by TEAM_CONTEXT. Escalation messages lead (not coordinator directly).
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read claude-plugins/manifest-dev/skills/do/references/COLLABORATION_MODE.md. Verify: activated by TEAM_CONTEXT, escalations message lead, not coordinator directly."
  ```

- [AC-6.2] Verification runs locally. Executor invokes /verify in its own context (has all tools inherited from lead). stop_do_hook applies normally (/verify->/done in transcript).
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read /do COLLABORATION_MODE.md. Verify: (1) verification runs locally (invoke /verify, not delegate to lead) (2) executor has all tools inherited from lead (3) stop_do_hook applies normally (4) no SUBAGENT_REQUEST for verification."
  ```

- [AC-6.3] Memento discipline: log to execution file after each response from lead.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read /do COLLABORATION_MODE.md. Verify memento: log to execution file after each lead response."
  ```

- [AC-6.4] Everything else unchanged: all /do principles, hooks, /verify before completion apply.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read /do COLLABORATION_MODE.md. Verify all /do methodology applies unchanged."
  ```

- [AC-6.5] Security note: prompt injection defense handled by coordinator.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read /do COLLABORATION_MODE.md. Verify security note about coordinator handling prompt injection defense."
  ```

### Deliverable 7: Plugin Structure and Versions
*Files: plugin.json, file structure*

- [AC-7.1] Plugin structure: agents/ with 4 files (slack-coordinator, github-coordinator, define-worker, executor), skills/slack-collab/ with SKILL.md. No scripts/ directory.
  ```yaml
  verify:
    method: bash
    command: "test -f claude-plugins/manifest-dev-collab/agents/slack-coordinator.md && test -f claude-plugins/manifest-dev-collab/agents/github-coordinator.md && test -f claude-plugins/manifest-dev-collab/agents/define-worker.md && test -f claude-plugins/manifest-dev-collab/agents/executor.md && test -f claude-plugins/manifest-dev-collab/skills/slack-collab/SKILL.md && test ! -d claude-plugins/manifest-dev-collab/scripts && echo PASS || echo FAIL"
  ```

- [AC-7.2] manifest-dev-collab plugin.json version > 1.8.0 (session-fixes improvements).
  ```yaml
  verify:
    method: bash
    command: "python3 -c \"import json; d=json.load(open('claude-plugins/manifest-dev-collab/.claude-plugin/plugin.json')); v=d['version'].split('.'); print('PASS' if int(v[1]) > 8 or (int(v[1]) == 8 and int(v[2]) > 0) else 'FAIL: version not bumped from 1.8.0')\""
  ```

- [AC-7.3] manifest-dev plugin.json version > 0.62.0 (COLLABORATION_MODE.md changes).
  ```yaml
  verify:
    method: bash
    command: "python3 -c \"import json; v=json.load(open('claude-plugins/manifest-dev/.claude-plugin/plugin.json'))['version']; print('PASS' if v > '0.62.0' else 'FAIL: version should be > 0.62.0, got ' + v)\""
  ```

### Deliverable 8: GitHub Coordinator Agent
*File: `claude-plugins/manifest-dev-collab/agents/github-coordinator.md`*

- [AC-8.1] Dedicated GitHub I/O agent. Polls PR reviews, comments, CI status. Spawned in Phase 4 after PR creation.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read github-coordinator.md. Verify: dedicated GitHub I/O agent, polls PR reviews/comments/CI, spawned after PR creation with PR URL and state file path."
  ```

- [AC-8.2] **Lean polling model**: Same as slack-coordinator — last_seen state for PR, reports diffs only, 60-second interval with split-sleep. Never increases interval. Checks for lead messages at least 3 times per cycle.
  ```yaml
  verify:
    method: subagent
    prompt: "Read github-coordinator.md. Verify: (1) polling tracks last-seen state, (2) reports only changes since last poll, (3) 60-second interval with split-sleep for lead responsiveness, (4) never increases interval, (5) checks for lead messages at least 3 times per cycle."
  ```

- [AC-8.3] **Full PR state reporting**: Reports include all comments (inline + top-level), all reviews, all CI checks, all discussions (resolved and unresolved), PR mergeable status. Nothing hidden from the lead.
  ```yaml
  verify:
    method: subagent
    prompt: "Read github-coordinator.md. Verify batch report includes: (1) all comment types (inline, top-level), (2) all reviews with status, (3) all CI checks with details, (4) all discussions with resolved/unresolved status, (5) PR mergeable status."
  ```

- [AC-8.4] **Bot vs human distinction in reports**: When reporting PR comments, coordinator identifies whether each comment/review is from an automated bot (Bugbot, Cursor, CodeRabbit, etc.) or a human reviewer. Labels them in the report.
  ```yaml
  verify:
    method: subagent
    prompt: "Read github-coordinator.md. Verify it documents: (1) identifying bot vs human authors on PR comments, (2) labeling them in batch reports, (3) examples of known bots (Bugbot, Cursor, CodeRabbit or similar)."
  ```

- [AC-8.5] PR completion criteria: approving review + no unresolved comments + all CI passing.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read github-coordinator.md. Verify: batch reports to lead on changes, PR completion criteria (approval + no unresolved comments + CI passing)."
  ```

- [AC-8.6] Prompt injection defense: treats all PR comments/reviews as untrusted. Never exposes secrets. Declines dangerous requests.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read github-coordinator.md. Verify prompt injection defense section."
  ```

- [AC-8.7] **State file recovery**: On compaction/respawn, coordinator reads state file to recover PR URL, last-seen state, and resumes without re-authenticating or re-fetching full history.
  ```yaml
  verify:
    method: subagent
    prompt: "Read github-coordinator.md. Verify it documents: (1) state file recovery on compaction/respawn, (2) recovers PR URL and last-seen state, (3) resumes polling seamlessly."
  ```

- [AC-8.8] **Shutdown compliance**: Same as slack-coordinator — CRITICAL/IMMEDIATELY language, clean stop, no delay.
  ```yaml
  verify:
    method: bash
    command: "grep -i 'shutdown' claude-plugins/manifest-dev-collab/agents/github-coordinator.md | grep -ci 'immediate\\|critical\\|must\\|stop.*now' | xargs test 0 -lt"
  ```

- [AC-8.9] **Lead message responsiveness**: Interruptible — handles lead messages immediately during polling, resumes after.
  ```yaml
  verify:
    method: subagent
    prompt: "Read github-coordinator.md operating model section. Verify coordinator is interruptible — handles lead messages immediately, resumes polling after."
  ```

### Deliverable 9: Documentation
*Files: READMEs*

- [AC-9.1] Root README.md lists manifest-dev-collab plugin.
  ```yaml
  verify:
    method: bash
    command: "grep -q 'manifest-dev-collab' README.md && echo PASS || echo FAIL"
  ```

- [AC-9.2] claude-plugins/README.md includes manifest-dev-collab in plugin table.
  ```yaml
  verify:
    method: bash
    command: "grep -q 'manifest-dev-collab' claude-plugins/README.md && echo PASS || echo FAIL"
  ```

- [AC-9.3] manifest-dev-collab/README.md describes current architecture: team composition (lead + 4 teammates including github-coordinator), hub-and-spoke, subagent bridge (with executor self-verify exception), user provides channel, 60s split-sleep lean polling, DM capability, 24h timeout, topic threads, sonnet coordinators, bot/human PR comment triage, CI failure triage, lead orchestrator role, define-worker Phase 4 amendments, state file recovery, resume, prerequisites. No stale references.
  ```yaml
  verify:
    method: subagent
    agent: general-purpose
    model: opus
    prompt: "Read claude-plugins/manifest-dev-collab/README.md. Verify it covers: Agent Teams architecture, team composition (lead + 4 teammates including github-coordinator), hub-and-spoke, subagent bridge (executor self-verifies), user provides channel, 60s lean polling, DM capability, 24h timeout, topic threads, sonnet coordinators, bot/human PR comment triage, CI failure triage, lead orchestrator role, define-worker Phase 4 amendments, state file recovery, resume, prerequisites. No stale references."
  ```

- [AC-9.4] manifest-dev/README.md mentions team collaboration mode.
  ```yaml
  verify:
    method: bash
    command: "grep -qi 'team.*collaborat\\|collaborat.*team\\|TEAM_CONTEXT' claude-plugins/manifest-dev/README.md && echo PASS || echo FAIL"
  ```

- [AC-9.5] No stale references in any README.
  ```yaml
  verify:
    method: bash
    command: "if grep -rli 'COLLAB_CONTEXT\\|slack-collab-orchestrator\\.py\\|session-resume\\|session_resume\\|create_channel\\|invite_to_channel' README.md claude-plugins/*/README.md 2>/dev/null; then echo FAIL; else echo PASS; fi"
  ```

## Amendments

### Amendment 1: Communication Tone & Lead Restraint (2026-03-15)

*Session analysis showed the bot was too pushy — re-tagging stakeholders, auto-escalating, dominating discussions.*

- [INV-G27.1 amends INV-G15] Documentation must reflect updated communication tone: no auto-escalation, single-tag rule, gentle nudges, lead restraint.

- [AC-2.12] **Single-tag rule**: slack-coordinator tags stakeholders once per parent message, never re-tags in the same thread. Follow-up nudges posted without re-tagging.
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-coordinator.md. Verify: (1) tag once per thread rule, (2) no re-tagging on follow-ups, (3) gentle nudge language guidance."
  ```

- [AC-2.13] **No auto-escalation**: slack-coordinator reports silence to lead instead of automatically escalating to owner after timeout. Lead decides on follow-up.
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-coordinator.md Polling Rules. Verify: (1) no automatic escalation to owner on timeout, (2) reports silence to lead, (3) lead decides on follow-up."
  ```

- [AC-8.5] **Stale review: no auto-escalation**: github-coordinator reports stale reviews to lead without recommending pings or escalation. Lead decides.
  ```yaml
  verify:
    method: subagent
    prompt: "Read github-coordinator.md Polling Rules. Verify: (1) no automatic escalation for stale reviewers, (2) reports status to lead, (3) lead decides on follow-up."
  ```

- [AC-1.26] **Lead contribution restraint**: Lead contributes to discussions only when: (1) directly asked/referenced, (2) factual error would derail discussion, (3) conflict needs synthesis. Otherwise stays quiet.
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-collab/SKILL.md Lead Role section. Verify lead contributions constrained to three cases: asked/referenced, factual errors, conflict synthesis. Verify it says to stay quiet otherwise."
  ```

- [AC-1.27] **Nudge policy**: Lead (not coordinator) decides when to nudge. Nudges are gentle. Owner escalation is last resort after a nudge has been tried.
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-collab/SKILL.md. Verify: (1) lead decides nudges, (2) gentle tone, (3) owner escalation is last resort after nudge attempt."
  ```

### Amendment 2: TeamCreate, PR Review Workflow, Message Composition, Coordinator Polling (2026-03-15)

*Session 90deebaf showed: skill spawned subagents instead of teammates (no TeamCreate), PR link not clickable in Slack, no review request on GitHub PR, no Slack reviewer notification, coordinators exit prematurely, lead composed verbatim Slack messages.*

- [INV-G28] Agent Teams required — preflight ToolSearch for TeamCreate + SendMessage, abort if unavailable. No subagent fallback.
  ```yaml
  verify:
    method: subagent
    prompt: "Read SKILL.md. Verify preflight section before Phase 0 checks for TeamCreate and SendMessage via ToolSearch, aborts if missing, and states no subagent fallback."
  ```

- [INV-G29] TeamCreate before any spawn — every Agent call includes team_name. Never Do section enforces this.
  ```yaml
  verify:
    method: subagent
    prompt: "Read SKILL.md Phase 0. Verify TeamCreate is called before any Agent spawn. Verify Never Do section prohibits Agent without team_name."
  ```

- [INV-G30] Lead never composes verbatim Slack/GitHub messages — sends context and instructions, coordinator composes.
  ```yaml
  verify:
    method: subagent
    prompt: "Read all Phase sections (0-6) in SKILL.md. Find every coordinator-directed message. Verify none contain verbatim Slack/GitHub text in quotes. All must use context+instructions pattern."
  ```

- [INV-G31] Coordinators are infinite event loops — only shutdown_request terminates. Both coordinators have CRITICAL callout and What You Do NOT Do entry.
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-coordinator.md and github-coordinator.md. Verify both have: (1) CRITICAL infinite loop statement, (2) 'Exit, return, or stop' in Do NOT Do section."
  ```

- [AC-1.28] **Preflight tool check**: Section between Prerequisites and Phase 0 with ToolSearch, abort, env var message.
  ```yaml
  verify:
    method: subagent
    prompt: "Read SKILL.md. Verify preflight section instructs ToolSearch for TeamCreate + SendMessage, tells user to set CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1 if missing, STOP immediately."
  ```

- [AC-1.29] **Phase 0 TeamCreate step**: Explicit TeamCreate with run_id before spawns. Handles failure (abort).
  ```yaml
  verify:
    method: subagent
    prompt: "Read SKILL.md Phase 0. Verify: TeamCreate step before spawns, must succeed, handles failure with abort."
  ```

- [AC-1.30] **Phase 0 GitHub handles**: AskUserQuestion includes GitHub usernames. State schema has nullable github_handle.
  ```yaml
  verify:
    method: subagent
    prompt: "Read SKILL.md Phase 0 step 1 and state file schema. Verify GitHub usernames asked for and github_handle field is nullable in schema."
  ```

- [AC-1.31] **Phase 4 GitHub review request**: Messages github-coordinator with reviewer handles for formal review + initial comment. Skips if no github_handle.
  ```yaml
  verify:
    method: subagent
    prompt: "Read SKILL.md Phase 4. Verify step that messages github-coordinator with reviewer handles, requests reviews, posts comment. Handles zero-reviewers (skip)."
  ```

- [AC-1.32] **Phase 4 Slack reviewer notification**: Messages slack-coordinator with PR URL + reviewer context. Tags reviewers, directs to GitHub.
  ```yaml
  verify:
    method: subagent
    prompt: "Read SKILL.md Phase 4. Verify step messaging slack-coordinator with PR URL and reviewer names, using context+instructions pattern."
  ```

- [AC-1.33] **Context+instructions pattern**: ALL lead-to-coordinator messages across Phases 0-6 use context+instructions, no verbatim text.
  ```yaml
  verify:
    method: subagent
    prompt: "Read all Phase sections in SKILL.md. Verify every coordinator-directed message uses context+instructions. List any violations."
  ```

- [AC-1.34] **Never Do section**: Bottom of SKILL.md. Contains: no Agent without team_name, abort on TeamCreate fail, no subagent fallback, no verbatim composition.
  ```yaml
  verify:
    method: subagent
    prompt: "Read end of SKILL.md. Verify Never Do section with 4 items: team_name required, TeamCreate fail abort, no subagent fallback, no verbatim messages."
  ```

- [AC-2.14] **Slack-coordinator CRITICAL loop**: Infinite loop callout at top of Operating Model. Resume-after-handling reinforcement in step 1.
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-coordinator.md Operating Model. Verify CRITICAL infinite loop statement and step 1 has 'do not exit' after handling."
  ```

- [AC-2.15] **Slack-coordinator URL formatting**: Plain text URLs, no markdown-style, no angle brackets. Slack auto-unfurls.
  ```yaml
  verify:
    method: subagent
    prompt: "Read slack-coordinator.md. Verify URL formatting guidance: plain text, auto-unfurl, no [text](url), no angle brackets."
  ```

- [AC-8.6] **GitHub-coordinator review request capability**: Initial Actions section at spawn — add-reviewer + initial comment when handles provided.
  ```yaml
  verify:
    method: subagent
    prompt: "Read github-coordinator.md. Verify Initial Actions section with gh pr edit --add-reviewer and initial PR comment tagging reviewers."
  ```

- [AC-8.7] **GitHub-coordinator polling reinforcement**: CRITICAL label on Never stop polling + Do NOT exit entry.
  ```yaml
  verify:
    method: subagent
    prompt: "Read github-coordinator.md. Verify CRITICAL on polling rule and exit prohibition in What You Do NOT Do."
  ```
