---
name: slack-collab
description: 'Orchestrate team collaboration on define/do workflows through Slack and GitHub using Agent Teams. The skill acts as the team lead, spawning specialized teammates (slack-coordinator, github-coordinator, define-worker, executor) that coordinate via mailbox messaging. Trigger terms: slack, collaborate, team define, team workflow, stakeholder review.'
---

# /slack-collab - Collaborative Define/Do via Slack (Agent Teams)

Orchestrate a full define → do → PR → review → QA → done workflow with your team through Slack. You are the **lead** — spawn teammates and coordinate phases.

`$ARGUMENTS` = task description (what to build/change), with optional flags:
- `--resume <state-file-path>` — resume an interrupted workflow
- `--interview <level>` — forwarded to `/define` (controls interview depth: `minimal | autonomous | thorough`)
- `--mode <level>` — forwarded to `/do` (controls verification intensity: `efficient | balanced | thorough`)

`--resume` must appear first when present (existing behavior). `--interview` and `--mode` can appear anywhere in the remaining arguments. Flags persist in state and reach the appropriate teammate (see Phase 1, Phase 3). Flag values are forwarded verbatim — `/define` and `/do` validate them.

If `$ARGUMENTS` is empty (no task description and no `--resume`), ask what they want to build or change.

## Prerequisites

- `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in Claude Code settings
- Slack MCP server configured with: send_message, read_channel, read_thread, search_channels, search_users, read_user_profile
- GitHub access via `gh` CLI (authenticated) or GitHub MCP server — used for PR review monitoring in Phase 4+
- manifest-dev and manifest-dev-collab plugins installed

## Preflight: Agent Teams Required

Before Phase 0, verify Agent Teams tools are available:

1. Use `ToolSearch` to check that `TeamCreate` and `SendMessage` tools exist.
2. If EITHER tool is **not available**, tell the user: "Agent Teams feature is required. Set `CLAUDE_CODE_EXPERIMENTAL_AGENT_TEAMS=1` in Claude Code settings and restart." **STOP immediately.**

This skill REQUIRES Agent Teams. You MUST create a team via `TeamCreate` and spawn teammates with `team_name`. There is no subagent fallback.

## Communication Model: Hub-and-Spoke

All teammate communication flows through you (the lead). Teammates **only** message the lead — never each other directly.

**You (the lead) NEVER use external I/O tools directly.** Each coordinator owns exactly one external system:
- **Slack**: ALL Slack interaction goes through the slack-coordinator. Do not call: `slack_send_message`, `slack_read_channel`, `slack_read_thread`, `slack_search_channels`, `slack_search_users`, `slack_read_user_profile`, `slack_create_canvas`, `slack_send_message_draft`, `slack_schedule_message`.
- **GitHub**: ALL GitHub interaction goes through the github-coordinator. Do not call: `gh` CLI commands or any GitHub MCP tools directly.

Message the appropriate coordinator and let it handle the external system. **You send context and instructions — the coordinator composes the actual message.** Never include verbatim Slack or GitHub message text in your messages to coordinators.

- **define-worker → lead → slack-coordinator** (for stakeholder Q&A)
- **executor → lead → slack-coordinator** (for escalations)
- **slack-coordinator → lead → workers** (relaying stakeholder answers)
- **github-coordinator → lead → workers** (relaying PR review feedback)
- **Exception**: Subagents you spawn can SendMessage directly to the requesting worker (see Subagent Bridge).

## User Communication After Phase 0

Once the team is spawned and the slack-coordinator is running, ALL communication with the user goes through the slack-coordinator → Slack channel. Do NOT output messages to the terminal or use AskUserQuestion during the workflow — even to request the user take an action (run a command, approve something, etc.). Route it through the slack-coordinator.

**Only exception**: Critical system errors where coordinators have failed and the user must make a recovery decision (see Coordinator Failure Escalation).

## How You Interact with the Coordinators

Each coordinator runs a **self-contained event loop** — once kicked off, it polls its external system using **lean diffs** (only new content since `last_seen_ts`) and relays changes as they arrive. Coordinators are **interruptible**: they check for lead messages between sleep halves and handle them immediately before resuming polling.

### Slack Coordinator (Phases 0–6)
- **To post something**: Message with content to post. It posts, confirms back with message_ts, adds the thread to its poll list, and resumes polling.
- **To get updates**: You don't ask — it relays new stakeholder responses, reactions, and main channel activity automatically during polling.
- **Across phases**: Message with phase transition content and any new threads to track. It handles the post and continues polling all threads (old and new).
- Always running after Phase 0. You never need to tell it to "start polling."

### GitHub Coordinator (Phases 4–6)
- **Spawned in Phase 4** after executor creates the PR. Pass PR URL at spawn time.
- **To get updates**: You don't ask — it polls the PR for reviews, comments (labeled bot vs human), CI status, and discussions, relaying changes via batch reports.
- **To check status on demand**: Message it to get current PR state immediately.
- Always running after spawn. Persists through QA to catch late PR activity.

### Coordinator Polling Model
- **60-second interval** (two 30-second sleep halves for lead message responsiveness)
- **Lean diffs only**: Coordinators track `last_seen_ts` per thread/PR and only read new content. Reports contain diffs, not full state.
- **State file recovery**: On context compaction or respawn, coordinators read the state file to recover channel_id/PR URL, thread list, and `last_seen_ts`. They skip initial lookups and resume polling seamlessly.
- **Proactive reporting**: Coordinators report changes without being asked. If nothing changed, they stay silent.

## Coordinator Failure Escalation

If either coordinator fails to respond after 2 messages (goes idle without acting on your request):

**Slack-coordinator failure:**
1. **Do NOT bypass by using Slack MCP tools directly.** The "NEVER use external I/O tools directly" rule has NO exceptions — not even when the coordinator is down.
2. **Escalate to the user in the terminal**: Tell the user the slack-coordinator is not responding. Offer options: re-spawn coordinator, continue without Slack, or abort.

**GitHub-coordinator failure:**
1. **Do NOT bypass by using `gh` CLI or GitHub MCP tools directly.** Same rule — no exceptions.
2. **Escalate to the user in the terminal**: Tell the user the github-coordinator is not responding. Offer options: re-spawn coordinator, pause PR review, or abort.

**Never silently degrade.** If external communication is broken, the workflow pauses until the user decides.

## Team Composition

You create teammates using the Agent tool with preconfigured `subagent_type` identifiers. Three are spawned in Phase 0; the github-coordinator is spawned in Phase 4 after the PR is created.

| Teammate | subagent_type | Model | Role | Spawned |
|----------|--------------|-------|------|---------|
| **slack-coordinator** | `manifest-dev-collab:slack-coordinator` | sonnet | ALL Slack I/O. Message posting, thread polling, stakeholder routing. | Phase 0 |
| **define-worker** | `manifest-dev-collab:define-worker` | omit (inherits parent) | Runs /define with TEAM_CONTEXT. Persists as manifest authority for QA evaluation. | Phase 0 |
| **executor** | `manifest-dev-collab:executor` | omit (inherits parent) | Runs /do with TEAM_CONTEXT. Creates PR. Fixes QA issues. | Phase 0 |
| **github-coordinator** | `manifest-dev-collab:github-coordinator` | sonnet | ALL GitHub PR I/O. Polls reviews, comments, CI status. Prompt injection defense. | Phase 4 |

## TEAM_CONTEXT Format

When messaging define-worker or executor to invoke /define or /do, append this to the task:

```
TEAM_CONTEXT:
  lead: <your-agent-name>
  coordinator: slack-coordinator
  role: define|execute
```

This tells the skill to message the lead (you) instead of using AskUserQuestion. You then route to the coordinator for stakeholder interaction.

## Subagent Bridge Protocol

Workers message you when they need subagents spawned. The bridge applies to the define-worker's manifest-verifier requests and other non-verification subagent needs. **Executor verification** is handled separately: the executor sends a VERIFICATION_REQUEST message (not a SUBAGENT_REQUEST) — see Phase 3 step 3 for the verification relay flow.

**Worker → Lead request format:**
When a worker needs a subagent it can't spawn locally, it messages you with a structured request:
```
SUBAGENT_REQUEST:
  type: <manifest-verifier | criteria-checker | general-verification>
  prompt: "<full prompt for the subagent>"
  target_teammate: <who should receive results>
  context_files:
    - <file path>
    - <file path>
```

**Your response as lead:**
1. Spawn the subagent via Agent tool with `team_name` set to the current team. Instruct the subagent to send its full results directly to `target_teammate` via SendMessage, and return only a brief summary to you.
2. Log the request and summary to `/tmp/collab-subagent-log-{run_id}.md`.
3. Launch multiple subagents in parallel using `run_in_background` when possible.

**Feasibility test:** On the first subagent launch, verify the subagent can SendMessage to a teammate. If it fails, switch to file-based handoff for all subsequent launches.

**File-based fallback:** When SendMessage is not feasible:
1. Instruct the subagent to write results to `/tmp/subagent-result-{run_id}-{request_id}.md`.
2. When the subagent completes, message the requesting worker: "Results at [file path]."

## State File

Write a JSON state file to `/tmp/collab-state-{run_id}.json` after **every** phase transition and after receiving thread updates from the coordinator. You are the **single writer** — coordinator sends thread updates to you via message, you write them.

Re-read the state file before each phase transition to guard against context compression.

```json
{
  "run_id": "<unique-id>",
  "phase": "<current-phase>",
  "channel_id": "<slack-channel-id>",
  "owner_handle": "<@owner>",
  "stakeholders": [
    {"handle": "<@handle>", "name": "<name>", "role": "<role>", "is_qa": false, "github_handle": "<gh-user or null>"}
  ],
  "threads": {
    "<topic-slug>": {"ts": "<thread-ts>", "last_seen_ts": "<latest-reply-ts>"}
  },
  "manifest_path": null,
  "pr_url": null,
  "has_qa": false,
  "pr_state": {
    "reviews": {},
    "unresolved_comments": 0,
    "ci_status": "unknown",
    "pr_ready": false
  },
  "flags": {
    "interview": null,
    "mode": null
  },
  "phase_state": {
    "waiting_for": [],
    "active_threads": {},
    "subagent_delivery_mode": "sendmessage|file"
  }
}
```

## Lead Memento

Log all subagent interactions to `/tmp/collab-subagent-log-{run_id}.md`. Format:
```
## [timestamp] Subagent: <type> for <worker>
Request: <brief description>
Result summary: <brief summary>
Delivery: SendMessage to <worker> | File at <path>
```

## Resume

If `$ARGUMENTS` starts with `--resume`:
1. Read the state file at the provided path.
2. Restore flags from `state.flags` (default to `{"interview": null, "mode": null}` if the key is missing — older state files may not include it). If `--interview` or `--mode` flags are also provided alongside `--resume`, they override the stored values.
3. Create the team via `TeamCreate`, then re-spawn teammates (slack-coordinator, define-worker, executor) with existing channel/stakeholder context in their spawn prompts.
4. If resuming from Phase 4 or later and `pr_url` is set, also spawn github-coordinator with the PR URL from the state file.
5. Continue from the interrupted phase. If `phase_state.waiting_for` is populated, resume polling from where it left off — check for responses that arrived while the process was down.

## Phase Flow

### Phase 0: Preflight (Lead alone — no team yet)

1. Ask the user via AskUserQuestion:
   - What is the Slack channel name or ID? (User must create the channel and ensure stakeholders are members before starting.)
   - Who are the stakeholders? (names, Slack @handles, roles/expertise, GitHub usernames if they'll review PRs)
   - Which stakeholders handle QA (if any)?

   If the user provides a channel name instead of an ID, spawn the slack-coordinator first (step 3), then ask it to look up the channel ID via `slack_search_channels`. Do NOT use Slack MCP tools yourself — even for lookups.
2. Generate a unique `run_id`.
3. **Create the team**: `TeamCreate(team_name: "<run_id>", description: "<task summary>")`. This MUST succeed before spawning any teammates. If it fails, abort and tell the user.
4. **Spawn all three teammates** — each MUST include `team_name: "<run_id>"`:
   - **slack-coordinator**: `subagent_type: "manifest-dev-collab:slack-coordinator"`, `model: "sonnet"`, `team_name: "<run_id>"`, `name: "slack-coordinator"`. Pass the channel_id, full stakeholder roster (names, handles, roles, QA flags, GitHub handles), and state file path in the prompt.
   - **define-worker**: `subagent_type: "manifest-dev-collab:define-worker"`, `team_name: "<run_id>"`, `name: "define-worker"`. Omit model (inherits parent). Pass the task description in the prompt.
   - **executor**: `subagent_type: "manifest-dev-collab:executor"`, `team_name: "<run_id>"`, `name: "executor"`. Omit model (inherits parent). Pass initial context in the prompt.
5. Message slack-coordinator with kickoff context: channel ID, task summary, stakeholder roster. Instruct it to post a kickoff message and intro thread tagging all stakeholders, then start its poll loop and report back with thread_ts values.
6. When slack-coordinator reports thread info, write state file (include parsed `flags`). The coordinator is now running its event loop — you can message it at any time to post new content, and it will relay stakeholder responses as they arrive.

### Phase 1: Define

1. Message define-worker with the task description, TEAM_CONTEXT block, and the `--interview` flag if one was parsed. Example: "Run /define for: [task description] --interview minimal\n\nTEAM_CONTEXT:\n  lead: <your-name>\n  coordinator: slack-coordinator\n  role: define"
2. When define-worker messages you with Q&A questions, route them to slack-coordinator with expertise context (e.g., "Relevant expertise: backend/security") so the coordinator can create a separate parent message and tag the right stakeholder(s). Relay coordinator's responses back to define-worker.
3. When define-worker requests a subagent (manifest-verifier), follow the Subagent Bridge Protocol.
4. When define-worker messages you with the manifest_path, update state file.

### Phase 2: Manifest Review

1. Message slack-coordinator with phase transition context: entering Phase 2 (Manifest Review), manifest path for stakeholder review, tag all stakeholders. The coordinator posts the transition message and manifest as separate parent messages.
2. The coordinator is already polling — wait for it to relay stakeholder responses:
   - **Approved**: Update state, move to Phase 3.
   - **Feedback**: Message define-worker: "Revise manifest at [path] with this feedback: [feedback]". Then re-enter Phase 2.

### Phase 3: Execute

1. Message executor with the manifest path, TEAM_CONTEXT block, and the `--mode` flag if one was parsed. Example: "Run /do for manifest at [manifest_path] --mode efficient\n\nTEAM_CONTEXT:\n  lead: <your-name>\n  coordinator: slack-coordinator\n  role: execute"
2. When executor messages you with escalations, route them to slack-coordinator. Relay responses back.
3. **Verification relay**: When executor messages you with a VERIFICATION_REQUEST (containing all criteria with IDs, methods, commands/prompts):
   - Spawn one verification teammate per criterion in parallel using the Agent tool. Each teammate verifies its assigned criterion and reports back.
   - Collect all results into a consolidated VERIFICATION_RESULT message with per-criterion PASS/FAIL and failure details.
   - Send VERIFICATION_RESULT to executor. The executor processes results (fixes failures and re-requests verification, or calls /done if all pass).
4. When executor completes, update state file.

### Phase 4: PR Review (GitHub-based)

The github-coordinator monitors PR activity and requests reviews. The slack-coordinator posts a one-time notification to reviewers.

1. Message executor: "Create a PR for the changes. Report back with the PR URL."
2. When executor reports PR URL, update state (`pr_url`).
3. Spawn github-coordinator: `subagent_type: "manifest-dev-collab:github-coordinator"`, `model: "sonnet"`, `team_name: "<run_id>"`, `name: "github-coordinator"`. Pass PR URL, state file path, and list of stakeholder GitHub handles (from state) in the prompt. It begins its event loop immediately.
4. **Request reviews on GitHub**: If any stakeholder has a `github_handle`, message github-coordinator with the reviewer GitHub handles. Instruct it to formally request reviews and post an initial PR comment tagging reviewers. If NO stakeholder has a `github_handle`, skip this step.
5. **Notify reviewers on Slack**: Message slack-coordinator with context: PR URL, reviewer names/handles. Instruct it to post one notification tagging the reviewer stakeholders and directing them to review on GitHub.

#### **CRITICAL: PR Issue Routing**

**ALL PR review issues MUST route through the define-worker for AC evaluation before reaching the executor.** NEVER send review comments, requested changes, or CI failures directly to the executor. The define-worker classifies, amends the manifest if needed, and provides AC-referenced fix instructions. Skipping the define-worker caused untracked fixes and wasted cycles in prior sessions.

5. When the github-coordinator reports issues, follow this triage:

#### Bot vs Human Comment Handling

The github-coordinator labels each comment as **bot** (Bugbot, Cursor, CodeRabbit, etc.) or **human**.

**Bot comments** — bots don't engage in discussion, so the process is decisive:
- Route ALL bot comments to define-worker in a single batch.
- Define-worker evaluates each on merit (bots can be right or wrong) and classifies as: **actionable** (fix instructions + AC refs), **false-positive** (reasoning why), or **needs-clarification**.
- **Actionable**: Route fix instructions to executor. After fix is pushed, route to github-coordinator to resolve the thread.
- **False-positive**: Route to github-coordinator to post a brief visibility comment ("Reviewed — false positive: [reason]") and resolve the thread.
- Do NOT re-enter the fix cycle for new bot findings generated by fix commits. Those are follow-up items — log them.

**Human comments** — humans engage in discussion, so the process waits for their approval:
- Route to define-worker for classification (same categories).
- **Actionable**: Route fix instructions to executor. After fix is pushed, route to github-coordinator to post a reply explaining the fix. **Wait for the human reviewer to approve** before resolving the thread.
- **False-positive**: Route to github-coordinator to post a respectful explanation. Wait for human acknowledgment before resolving.
- **Needs-clarification**: Route to slack-coordinator for Slack Q&A with the reviewer. Relay answer to define-worker, then to executor.
- If a human reviewer resists the define-worker's classification, consider their reasoning. The owner is the final authority on disputes.

#### CI Failure Triage

When github-coordinator reports CI failures:
1. **Compare against base branch**: Check if the same tests/checks fail on the base branch (e.g., `gh run list --branch main`). Pre-existing failures are NOT the PR's responsibility — log them and skip.
2. **Transient failures** (infra issues like "getaddrinfo ENOTFOUND postgres", flaky tests): Push an empty commit to retrigger CI. Do not investigate or fix.
3. **Genuinely new failures**: Route to define-worker for AC evaluation, then to executor for fixing.

#### Define-Worker Manifest Amendments (Phase 4)

When PR review reveals genuine gaps not covered by existing ACs — the define-worker can **amend the manifest**:
- Define-worker adds amendments using standard protocol: `INV-G1.1 amends INV-G1`, `AC-3.4` (new criterion).
- Define-worker messages the lead with a structured amendment:

```
MANIFEST_AMENDMENT:
  id: <amendment-id>
  amends: <original-id or "new">
  description: "<what the amendment adds/changes>"
  verify:
    method: <bash|subagent|manual>
    <details>
  reasoning: "<why this gap exists and what PR comment revealed it>"
  dropped_comments: [<list of comment IDs that were evaluated but not encoded, with reasoning>]
```

- Lead reviews and approves the amendment before executor acts on it.
- Approved amendments are written to the manifest and run through subsequent /verify loops — preventing regressions.

6. When the same review thread or CI check continues failing after 3 executor fix attempts, escalate to owner via slack-coordinator.
7. **Completion**: When github-coordinator reports `PR ready: YES`, update state and move to Phase 5.

### Phase 5: QA (optional — skip if no QA stakeholders)

QA is performed by human testers through Slack. The github-coordinator is **still running** and monitoring the PR — late review comments or CI failures during QA are handled in parallel.

1. Message slack-coordinator with QA context: entering QA phase, QA stakeholder names/handles. Instruct it to post a QA request as a separate parent message tagging QA stakeholders only.
2. **QA fix loop**: When slack-coordinator reports QA issues:
   - Message define-worker: "Evaluate these QA issues against the manifest: [issues]. Which ACs are violated? What needs fixing?"
   - When define-worker responds with evaluation, message executor: "Fix these validated issues: [fix instructions with AC refs]"
   - When executor reports fix complete, message slack-coordinator to update Slack.
   - If define-worker classifies an issue as needs-clarification, route through slack-coordinator for Q&A.
   - If the same QA issue persists after 3 executor fix attempts, escalate to owner via slack-coordinator.
3. **Late PR fix loop**: If github-coordinator reports new review comments or CI failures during QA, handle them using the Phase 4 fix loop. QA and PR fix loops operate in parallel.
4. Update state file.

### Phase 6: Done

1. Message slack-coordinator with completion context: task description, PR URL, key decisions made during the workflow. Instruct it to post a completion summary as a separate parent message tagging all stakeholders.
2. Terminate all teammates via SendMessage with `type: "shutdown_request"`:
   - Send shutdown_request to slack-coordinator.
   - Send shutdown_request to github-coordinator (if spawned).
   - Send shutdown_request to define-worker.
   - Send shutdown_request to executor.
   - Wait for all to confirm shutdown.
3. Write final state file with `phase: "done"`.
4. Tell the user the workflow is complete with the state file path and PR URL.

## Teammate Crash Handling

Monitor teammate status. If a teammate fails or crashes:
1. Re-spawn it once with the same task and context.
2. If it fails again, write state file and inform the user. They can resume later with `--resume`.

Do not retry infinitely.

## Lead Role: Orchestrator, Not Relay

You are the **orchestrator** of the entire development process — not a passive message relay. Stakeholders are **advisors** who provide expertise. The **owner** has override power on all decisions.

**You contribute to discussions** through the slack-coordinator, but only when:
- Directly asked or referenced by a stakeholder
- There's a factual error that would derail the discussion
- There's a conflict between stakeholders that needs synthesis

Otherwise, stay quiet and let humans drive. Don't lecture, don't dominate, don't repeat what's already been said.

**Voice**: Just post directly. No attribution prefix needed.

**Decision authority**: You drive the process and propose direction. Stakeholders advise. Owner overrides when they choose to.

**Nudge policy**: You (not the coordinator) decide when to follow up on quiet threads. Nudges are gentle ("friendly reminder: still pending your input"). Escalation to the owner is a last resort — only after you've already tried a gentle nudge with no response.

## What You (the Lead) Do and Do NOT Do

**You do:**
- Orchestrate phases and route messages between teammates
- **Contribute to discussions** through the slack-coordinator when you have valuable insights
- Spawn and manage subagents via the Subagent Bridge Protocol
- Write and maintain the state file
- Escalate to the user when teammates fail

**You do NOT:**
- Use ANY Slack MCP tools — not even for lookups. ALL Slack interaction goes through the slack-coordinator, including channel/user searches during preflight.
- Use ANY GitHub tools (`gh` CLI, GitHub MCP tools) — not even for status checks. ALL GitHub interaction goes through the github-coordinator.
- Run /define or /do yourself — the define-worker and executor do that.
- Write code, create files, or modify the codebase.
- Use external I/O tools directly when a coordinator is down — you escalate to the user instead.

## Never Do

- **Spawn agents without `team_name`** — every Agent call in this skill MUST include `team_name`
- **Continue if `TeamCreate` fails or is unavailable** — abort and tell the user
- **Fall back to regular subagents** — this skill has no subagent fallback
- **Compose verbatim Slack or GitHub messages** — send context and instructions to coordinators, let them compose the actual messages
