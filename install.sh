#!/bin/bash
# install.sh — Install or update Copilot skills from azlanhussain/copilot-skills
# Usage: bash install.sh
# Or one-liner: curl -s https://raw.githubusercontent.com/azlanhussain/copilot-skills/main/install.sh | bash

set -e

REPO_URL="https://github.com/azlanhussain/copilot-skills.git"
CLONE_DIR="$HOME/.copilot-skills-src"
SKILLS_DIR="$HOME/.copilot/skills"

echo "🤖 Copilot Skills Installer"
echo "==========================="

# Step 1: Clone or update the repo
if [ -d "$CLONE_DIR/.git" ]; then
  echo "📦 Updating skills from repo..."
  git -C "$CLONE_DIR" pull --quiet
else
  echo "📦 Downloading skills..."
  git clone --quiet "$REPO_URL" "$CLONE_DIR"
fi

# Step 2: Ensure skills directory exists
mkdir -p "$SKILLS_DIR"

# Step 3: Copy each skill folder (skip non-skill files)
echo ""
echo "📂 Installing skills to $SKILLS_DIR"
for skill_dir in "$CLONE_DIR"/*/; do
  skill_name=$(basename "$skill_dir")
  # Skip non-skill entries (no SKILL.md)
  if [ ! -f "$skill_dir/SKILL.md" ]; then
    continue
  fi
  cp -r "$skill_dir" "$SKILLS_DIR/"
  echo "   ✅ $skill_name"
done

echo ""
echo "✅ Done! The following skills are now available:"
for skill_dir in "$SKILLS_DIR"/*/; do
  skill_name=$(basename "$skill_dir")
  if [ -f "$skill_dir/SKILL.md" ]; then
    desc=$(grep "description:" "$skill_dir/SKILL.md" 2>/dev/null | head -1 | sed 's/description://' | sed "s/^[[:space:]]*//" | sed "s/>-//")
    echo "   • $skill_name"
  fi
done

echo ""
echo "💡 Usage: In any Copilot CLI session, just say the skill name e.g.:"
echo "   openqc-prepare"
echo "   openqc-run"
echo "   fix-review"
