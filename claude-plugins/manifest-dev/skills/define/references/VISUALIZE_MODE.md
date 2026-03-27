# Visualize Mode — /define

This file is loaded when `--visualize` is present and medium is `local`. If `--visualize` is absent, this file should not have been loaded.

## Purpose

The define interview can feel like an interrogation. The user answers questions in a terminal without seeing the bigger picture — why each question matters, what's been explored, what's still foggy. The visualization is a **companion window** that makes the model's reasoning visible.

**UX progression**: Starts as ambient — a glanceable orientation tool the user notices between answers. Becomes active as they engage — a thinking aid that helps them surface better requirements and see connections they'd miss from text alone.

## What to Show

Two content pillars, both updated after each interview step:

**Coverage map** — Which areas of the task have been explored (solid/clear) vs. remain unknown (foggy/dim). Areas emerge from domain grounding and expand through pre-mortem, backcasting, and user responses. The user sees at a glance where depth exists and where gaps remain.

**Question rationale** — For each question asked, a brief explanation of what risk, failure scenario, or complexity it's probing. "I'm asking about X because [concrete scenario where ignoring X causes failure]." The user understands WHY, not just WHAT.

## Experience

**Visual mood**: A calm thinking space — muted palette, generous whitespace, clear typographic hierarchy. The visualization complements the terminal without competing for attention. It should feel like a focused companion, not a control panel.

**Progress and momentum**: As the interview advances, explored areas should feel increasingly solid and clear. The user should sense "we're getting somewhere" — fog lifting, coverage growing, gaps narrowing. This rewards engagement and encourages the user to volunteer information proactively.

**Seamless updates**: Content flows in naturally after each interview step. No jarring page reloads, no flashing, no layout jumps. The page feels alive and continuous — updated, not rebuilt.

## Avoid

- **Wall of text** — rationale as dense paragraphs nobody reads. Use structure, not prose.
- **Information overload** — showing everything at once. Reveal progressively as the interview unfolds.
- **Clinical sterility** — technically correct but lifeless. Craft matters — the visualization should feel like something a human designed, not a debug dump.
- **Jarring transitions** — full page reloads, content jumping, scroll position lost. Updates should feel invisible.

## Lifecycle

**Setup**: Make the visualization accessible to the user during the interview session. Working files belong in `/tmp/`.

**Updates**: The visualization stays current with the interview's progress — reflecting what's been covered, what's still unknown, and why the latest questions matter.

**Cleanup**: Clean up all visualization resources (server processes, open ports, temporary files) when `/define` completes or the session ends. Resources should also be cleaned up if the session is interrupted mid-interview. If cleanup fails, it's acceptable — `/tmp/` files are ephemeral and orphaned processes on random ports are low-impact.

**Graceful degradation**: If any visualization step fails, continue the interview normally. The visualization enhances `/define` — it never blocks it.

## Constraints

- The interview drives the pace. Visualization updates must not delay questions.
- No external templating dependencies.
- The visualization should feel crafted — something the user enjoys glancing at, not tolerates.
