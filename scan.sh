#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Skill Optimizer by Stel
# https://github.com/Stel777/Skill-Optimizer
#
# Scans available skills and add-ons and injects them as context for Claude
# to analyze and recommend at the start of a new project.
#
# CONFIGURATION (override via environment variables):
#   SKILL_OPTIMIZER_SKILLS_DIR   — path to your Claude skills folder
#   SKILL_OPTIMIZER_ADDONS_DIR   — path to your add-ons folder
#
# Defaults:
#   SKILLS_DIR = ~/.claude/skills
#   ADDONS_DIR = ~/Documents/Claude_Stuff/Add-Ons
# ─────────────────────────────────────────────────────────────────────────────

SKILLS_DIR="${SKILL_OPTIMIZER_SKILLS_DIR:-$HOME/.claude/skills}"
ADDONS_DIR="${SKILL_OPTIMIZER_ADDONS_DIR:-$HOME/Documents/Claude_Stuff/Add-Ons}"
MARKER_FILE=".skill-optimizer-ran"

# Only run once per project directory
if [ -f "$MARKER_FILE" ]; then
  exit 0
fi

# Only run if skills or add-ons directories exist
if [ ! -d "$SKILLS_DIR" ] && [ ! -d "$ADDONS_DIR" ]; then
  exit 0
fi

echo ""
echo "╔══════════════════════════════════════════════════════════╗"
echo "║           SKILL OPTIMIZER — PROJECT START SCAN           ║"
echo "╚══════════════════════════════════════════════════════════╝"
echo ""

# ── Scan Skills ──────────────────────────────────────────────────────────────
if [ -d "$SKILLS_DIR" ]; then
  echo "AVAILABLE SKILLS:"
  found_skills=0
  for d in "$SKILLS_DIR"/*/; do
    name=$(basename "$d")
    # Skip skill-optimizer itself
    if [ "$name" = "skill-optimizer" ]; then
      continue
    fi
    if [ -f "$d/SKILL.md" ]; then
      desc=$(grep -m1 '^description:' "$d/SKILL.md" 2>/dev/null | sed 's/^description:[[:space:]]*//' | tr -d '"')
      if [ -n "$desc" ]; then
        echo "  • $name — $desc"
      else
        echo "  • $name"
      fi
      found_skills=1
    fi
  done
  if [ "$found_skills" -eq 0 ]; then
    echo "  (no skills found)"
  fi
  echo ""
fi

# ── Scan Add-Ons ─────────────────────────────────────────────────────────────
if [ -d "$ADDONS_DIR" ]; then
  echo "AVAILABLE ADD-ONS:"
  found_addons=0
  for d in "$ADDONS_DIR"/*/; do
    if [ -d "$d" ]; then
      name=$(basename "$d")
      # Try to pull a short description from README
      readme_line=$(grep -m3 -v '^#' "$d/README.md" 2>/dev/null | grep -v '^[[:space:]]*$' | head -1 | cut -c1-120)
      if [ -n "$readme_line" ]; then
        echo "  • $name — $readme_line"
      else
        echo "  • $name"
      fi
      found_addons=1
    fi
  done
  if [ "$found_addons" -eq 0 ]; then
    echo "  (no add-ons found)"
  fi
  echo ""
fi

# ── Instructions for Claude ──────────────────────────────────────────────────
echo "──────────────────────────────────────────────────────────────"
echo "[skill-optimizer] INSTRUCTIONS FOR CLAUDE:"
echo "Before responding to the user's project idea, do the following:"
echo ""
echo "1. Review the skills and add-ons listed above."
echo "2. Based on the user's project idea, identify which are relevant."
echo "3. For each relevant item, state:"
echo "     - Name of the skill/add-on"
echo "     - Why it is relevant to this specific project"
echo "     - Where/how it would be used during the build"
echo "4. Ask the user: 'Would you like me to activate these for the project?'"
echo "5. Wait for confirmation before proceeding."
echo "6. After presenting your recommendations, create the file: $MARKER_FILE"
echo "──────────────────────────────────────────────────────────────"
echo ""
