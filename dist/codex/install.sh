#!/usr/bin/env bash
set -euo pipefail

# manifest-dev installer/updater for Codex CLI
# Run: bash install.sh
# Or:  curl -sSL <raw-url>/install.sh | bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing manifest-dev for Codex CLI..."

# Skills → .agents/skills/ (Codex standard path)
mkdir -p ".agents/skills"
cp -r "$SCRIPT_DIR/skills/"* ".agents/skills/"
echo "  Skills: $(ls "$SCRIPT_DIR/skills/" | wc -l | tr -d ' ') installed"

# AGENTS.md
cp "$SCRIPT_DIR/AGENTS.md" "./AGENTS.md"
echo "  Context: AGENTS.md installed"

# Agent TOML stubs
mkdir -p ".codex/agents"
cp "$SCRIPT_DIR/agents/"*.toml ".codex/agents/"
echo "  Agents: $(ls "$SCRIPT_DIR/agents/" | wc -l | tr -d ' ') TOML stubs installed"

# Execution rules
mkdir -p ".codex/rules"
cp "$SCRIPT_DIR/rules/default.rules" ".codex/rules/"
echo "  Rules: default.rules installed"

# Config — don't overwrite, just remind
if [ -f ".codex/config.toml" ]; then
  echo "  Config: .codex/config.toml exists — merge manually from dist/codex/config.toml"
else
  cp "$SCRIPT_DIR/config.toml" ".codex/config.toml"
  echo "  Config: config.toml installed"
fi

echo ""
echo "Done! Skills are ready to use."
echo "Agent TOML stubs and rules provide multi-agent support (limited to shell + apply_patch)."
echo "Hooks are not available — Codex hook system expected mid-March 2026."
