#!/usr/bin/env bash
set -euo pipefail

# manifest-dev installer/updater for Gemini CLI
# Run: bash install.sh
# Or:  curl -sSL <raw-url>/install.sh | bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing manifest-dev for Gemini CLI..."

# Detect project vs global install
if [ -d ".gemini" ] || [ -d ".git" ]; then
  TARGET=".gemini"
  echo "  Target: project (.gemini/)"
else
  TARGET="$HOME/.gemini"
  echo "  Target: global (~/.gemini/)"
fi

# Skills
mkdir -p "$TARGET/skills"
cp -r "$SCRIPT_DIR/skills/"* "$TARGET/skills/"
echo "  Skills: $(ls "$SCRIPT_DIR/skills/" | wc -l | tr -d ' ') installed"

# Agents
mkdir -p "$TARGET/agents"
cp -r "$SCRIPT_DIR/agents/"* "$TARGET/agents/"
echo "  Agents: $(ls "$SCRIPT_DIR/agents/" | wc -l | tr -d ' ') installed"

# Hooks
mkdir -p "$TARGET/hooks"
cp "$SCRIPT_DIR/hooks/"*.py "$TARGET/hooks/"
cp "$SCRIPT_DIR/hooks/hooks.json" "$TARGET/hooks/"
echo "  Hooks: adapter + $(ls "$SCRIPT_DIR/hooks/"*.py | wc -l | tr -d ' ') hooks installed"

# Context file
cp "$SCRIPT_DIR/GEMINI.md" "$TARGET/GEMINI.md"
echo "  Context: GEMINI.md installed"

# Check enableAgents
echo ""
echo "Done! Make sure your settings.json includes:"
echo '  { "experimental": { "enableAgents": true } }'
echo ""
echo "And merge hooks/hooks.json entries into your settings.json hooks section."
