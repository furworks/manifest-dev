import type { Plugin } from "@opencode-ai/plugin"

/**
 * manifest-dev workflow enforcement hooks for OpenCode.
 *
 * Implements three hooks from the Claude Code manifest-dev plugin:
 * 1. PreToolUse (verify context reminder) → tool.execute.before
 * 2. Stop (do workflow enforcement) → session.idle
 * 3. PostCompact (workflow recovery) → experimental.session.compacting
 *
 * See HOOK_SPEC.md for full behavioral specification.
 *
 * IMPORTANT: This is a stub — the Python hook logic must be ported
 * to TypeScript. The structure and event bindings are correct;
 * the implementation bodies need to be filled in.
 */

export const ManifestDevPlugin: Plugin = async (ctx) => {
  return {
    // Hook 1: Verify context reminder (PreToolUse → tool.execute.before)
    // When /verify skill is about to be invoked, remind to read manifest + log
    "tool.execute.before": async ({ tool, sessionID, callID }, { args }) => {
      if (tool !== "skill") return

      const skillName = (args as Record<string, unknown>)?.skill as string
      if (!skillName) return

      const isVerify = skillName === "verify" || skillName.endsWith(":verify")
      if (!isVerify) return

      // TODO: Port pretool_verify_hook.py logic
      // Add system reminder to read manifest and execution log before verification
      // OpenCode blocking pattern: set args.abort = "reason" to block
      // For context injection, use the plugin's context injection mechanism
      console.error("[manifest-dev] Verify context reminder: read manifest + log before spawning verifiers")
    },

    // Hook 2: Stop enforcement (Stop → session.idle)
    // Block premature stops during /do workflow
    "session.idle": async (event) => {
      // TODO: Port stop_do_hook.py logic
      // 1. Parse transcript to detect /do workflow state
      // 2. If /do active but no /done or /escalate, the session should not stop
      // 3. OpenCode limitation: session.idle is NOT blocking — cannot prevent stop
      //    This is a known gap. Log a warning instead.
      // 4. Consider using tool.execute.before on all tools to check workflow state
      console.error("[manifest-dev] Session idle during active /do workflow — verify completion manually")
    },

    // Hook 3: Post-compact recovery (PreCompact → experimental.session.compacting)
    // Restore /do workflow context after compaction
    "experimental.session.compacting": async (event) => {
      // TODO: Port post_compact_hook.py logic
      // 1. Parse transcript to detect active /do workflow
      // 2. If active, inject reminder to re-read manifest and execution log
      // 3. This event is experimental in OpenCode — may change
      console.error("[manifest-dev] Session compacted during /do workflow — re-read manifest + log")
    },
  }
}
