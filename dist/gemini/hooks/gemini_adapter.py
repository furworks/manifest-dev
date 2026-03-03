#!/usr/bin/env python3
"""
Gemini CLI adapter for Claude Code hooks.

Translates between Gemini CLI hook protocol and Claude Code hook protocol.
Gemini uses different field names but similar JSON stdin/stdout pattern.

Usage: python3 gemini_adapter.py <hook_module> [hook_function]
  Reads Gemini JSON from stdin, translates to Claude Code format,
  calls the hook, translates output back to Gemini format.
"""

from __future__ import annotations

import importlib
import json
import sys
from io import StringIO


def translate_gemini_to_claude(gemini_input: dict, event: str) -> dict:
    """Translate Gemini hook input to Claude Code hook input format."""
    claude_input = {
        "transcript_path": gemini_input.get("transcript_path", ""),
        "session_id": gemini_input.get("session_id", ""),
        "cwd": gemini_input.get("cwd", ""),
    }

    if event == "BeforeTool":
        claude_input["tool_name"] = gemini_input.get("tool_name", "")
        claude_input["tool_input"] = gemini_input.get("tool_input", {})
        # Map Gemini tool names back to Claude Code names for hook logic
        tool_remap = {
            "activate_skill": "Skill",
            "run_shell_command": "Bash",
            "read_file": "Read",
            "write_file": "Write",
            "replace": "Edit",
            "search_file_content": "Grep",
            "glob": "Glob",
            "web_fetch": "WebFetch",
            "google_web_search": "WebSearch",
        }
        original_name = claude_input["tool_name"]
        claude_input["tool_name"] = tool_remap.get(original_name, original_name)

    elif event == "AfterAgent":
        claude_input["stop_hook_active"] = True

    return claude_input


def translate_claude_to_gemini(claude_output: dict, event: str) -> dict:
    """Translate Claude Code hook output to Gemini hook output format."""
    gemini_output = {}

    hook_specific = claude_output.get("hookSpecificOutput", {})

    # Handle permission decisions (PreToolUse -> BeforeTool)
    if event == "BeforeTool":
        permission = hook_specific.get("permissionDecision", "")
        if permission == "deny":
            gemini_output["decision"] = "deny"
            gemini_output["reason"] = hook_specific.get(
                "permissionDecisionReason", "Blocked by hook"
            )
        additional = hook_specific.get("additionalContext", "")
        if additional:
            gemini_output["hookSpecificOutput"] = {
                "additionalContext": additional
            }

    # Handle stop/block decisions (Stop -> AfterAgent)
    elif event == "AfterAgent":
        decision = claude_output.get("decision", "")
        if decision == "block":
            gemini_output["decision"] = "deny"
            gemini_output["reason"] = claude_output.get(
                "reason", "Blocked by hook"
            )
        system_msg = claude_output.get("systemMessage", "")
        if system_msg:
            gemini_output["systemMessage"] = system_msg

    # Handle additionalContext for any event
    elif event in ("SessionStart", "PreCompress"):
        additional = hook_specific.get("additionalContext", "")
        if additional:
            gemini_output["hookSpecificOutput"] = {
                "additionalContext": additional
            }

    return gemini_output


def main() -> None:
    if len(sys.argv) < 2:
        print("Usage: gemini_adapter.py <hook_module> [event_override]", file=sys.stderr)
        sys.exit(1)

    hook_module_name = sys.argv[1]
    event_override = sys.argv[2] if len(sys.argv) > 2 else None

    try:
        stdin_data = sys.stdin.read()
        gemini_input = json.loads(stdin_data)
    except (json.JSONDecodeError, OSError):
        sys.exit(0)

    event = event_override or gemini_input.get("hook_event_name", "")

    # Translate input
    claude_input = translate_gemini_to_claude(gemini_input, event)

    # Import and run the Claude Code hook by capturing its stdout
    hook_module = importlib.import_module(hook_module_name)

    # Redirect stdin for the hook
    old_stdin = sys.stdin
    sys.stdin = StringIO(json.dumps(claude_input))

    # Capture stdout
    old_stdout = sys.stdout
    sys.stdout = StringIO()

    try:
        hook_module.main()
    except SystemExit:
        pass  # hooks use sys.exit(0)

    hook_stdout = sys.stdout.getvalue()
    sys.stdin = old_stdin
    sys.stdout = old_stdout

    # Parse hook output and translate
    if hook_stdout.strip():
        try:
            claude_output = json.loads(hook_stdout)
            gemini_output = translate_claude_to_gemini(claude_output, event)
            if gemini_output:
                print(json.dumps(gemini_output))
        except json.JSONDecodeError:
            pass

    sys.exit(0)


if __name__ == "__main__":
    main()
