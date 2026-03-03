#!/usr/bin/env bash
set -euo pipefail

# manifest-dev installer/updater for OpenCode
# Run: bash install.sh
# Or:  curl -sSL <raw-url>/install.sh | bash

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

echo "Installing manifest-dev for OpenCode..."

# Detect project vs global install
if [ -d ".opencode" ] || [ -d ".git" ]; then
  TARGET=".opencode"
  echo "  Target: project (.opencode/)"
else
  TARGET="$HOME/.config/opencode"
  echo "  Target: global (~/.config/opencode/)"
fi

# Skills
mkdir -p "$TARGET/skills"
cp -r "$SCRIPT_DIR/skills/"* "$TARGET/skills/"
echo "  Skills: $(ls "$SCRIPT_DIR/skills/" | wc -l | tr -d ' ') installed"

# Agents
mkdir -p "$TARGET/agents"
cp -r "$SCRIPT_DIR/agents/"* "$TARGET/agents/"
echo "  Agents: $(ls "$SCRIPT_DIR/agents/" | wc -l | tr -d ' ') installed"

# Commands
mkdir -p "$TARGET/commands"
cp -r "$SCRIPT_DIR/commands/"* "$TARGET/commands/"
echo "  Commands: $(ls "$SCRIPT_DIR/commands/" | wc -l | tr -d ' ') installed"

# Plugins (stubs — won't overwrite existing implementations)
mkdir -p "$TARGET/plugins"
for f in "$SCRIPT_DIR/plugins/"*; do
  fname=$(basename "$f")
  if [ -f "$TARGET/plugins/$fname" ] && [ "$fname" = "index.ts" ]; then
    echo "  Plugins: index.ts exists — skipping (won't overwrite manual port)"
  else
    cp "$f" "$TARGET/plugins/$fname"
  fi
done
echo "  Plugins: stubs installed (see HOOK_SPEC.md for implementation guide)"

# Install plugin dependencies if bun available
if [ -f "$TARGET/plugins/package.json" ]; then
  if command -v bun &>/dev/null; then
    (cd "$TARGET/plugins" && bun install --silent 2>/dev/null) && echo "  Dependencies: installed via bun" || echo "  Dependencies: bun install failed — run manually: cd $TARGET/plugins && bun install"
  else
    echo "  Dependencies: bun not found — run: cd $TARGET/plugins && npm install"
  fi
fi

# AGENTS.md
cp "$SCRIPT_DIR/AGENTS.md" "./AGENTS.md" 2>/dev/null || cp "$SCRIPT_DIR/AGENTS.md" "$TARGET/AGENTS.md"
echo "  Context: AGENTS.md installed"

echo ""
echo "Done! Skills and agents are ready to use."
echo "Hooks are stubs only — see plugins/HOOK_SPEC.md to implement."
