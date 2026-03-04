# SKILL Task Guidance

Creating or improving Claude Code skills or agent skills. Composes with PROMPTING.md.

## Quality Gates

- **Progressive disclosure** — Skill body under 500 lines; reference files organized in references/ with clear loading pointers from SKILL.md; no single-file context overload | Verify: line count + directory structure check
- **Instruction transparency** — All rigid directives (MUST/NEVER/ALWAYS) accompanied by reasoning explaining why the constraint matters. LLMs generalize better from understanding than from rigid rules without context | Verify: scan for rigid directives, check each has adjacent explanation

## Context to Discover

Beyond PROMPTING.md's general context probes, surface these before defining a skill:

| Context Type | What to Surface | Probe |
|--------------|-----------------|-------|
| **Existing skills** | Similar skills already available, duplication risk | What skills exist in this area? Would this overlap? |
| **Target platform** | Claude Code, Claude.ai, Cowork — affects available capabilities | Where will this skill run? Subagents available? Browser? |
| **Audience expertise** | Developer, non-technical, mixed — affects communication style within the skill | Who will invoke this skill? What jargon is safe? |
| **Tool requirements** | MCPs, scripts, file access, subagents the skill needs | What tools must be available? Any external dependencies? |
| **Invocation mode** | Auto-invoked, user-invoked (/slash), programmatic (skill-from-skill) | How will this skill be triggered? Multiple modes? |

## Risks

- **Context overload** — skill tries to load everything into SKILL.md body instead of using layered references; probe: can content be split into body + references/?
- **Script reinvention** — every invocation independently writes the same helper scripts; probe: are there deterministic/repetitive operations that should be bundled in scripts/?
- **Platform mismatch** — skill depends on capabilities unavailable on target platform (subagents, browser, CLI tools); probe: what platform features does this require?

## Scenario Prompts

- **Undertriggering** — skill exists but Claude never invokes it because description is too narrow, too generic, or uses wrong vocabulary; probe: tested description against realistic user phrasings?
- **Overtriggering** — skill fires for irrelevant queries, polluting unrelated workflows; probe: what near-miss queries should NOT trigger this skill?
- **Author-bias** — skill works for creator's test cases but fails on diverse real-user phrasings and contexts; probe: tested with prompts outside the author's mental model?
- **Skill collision** — multiple skills compete for the same query, causing unpredictable invocation; probe: how does this skill differentiate from adjacent skills in the description?

## Trade-offs

- Generic coverage vs specialized precision
- Pushy description (risk overtrigger) vs conservative description (risk undertrigger)
- All-in-body vs layered references (simplicity vs context efficiency)
- Bundled scripts vs inline generation (reliability and speed vs flexibility)

## Defaults

*Domain best practices for this task type.*

- **Eval-driven iteration** — Test skill against realistic prompts with baseline comparison (with-skill vs without-skill); iterate based on observed results rather than assumptions about what will work
- **Generalize from feedback** — Improve based on patterns across test cases, not fiddly case-specific fixes that overfit to examples; the skill must work across many prompts, not just the test set
- **Keep prompt lean** — Remove instructions not pulling their weight; read execution transcripts to identify unproductive patterns the skill causes
- **Invoke skill-creator if available** — When the skill-creator skill (or equivalent) is available, use it for systematic eval-driven development rather than manual iteration
