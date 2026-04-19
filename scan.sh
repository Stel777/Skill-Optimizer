#!/bin/bash
# ─────────────────────────────────────────────────────────────────────────────
# Skill Optimizer by Stel — v2.1
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
CACHE_FILE="${HOME}/.claude/skill-optimizer-cache.md"

# Only run if skills or add-ons directories exist
if [ ! -d "$SKILLS_DIR" ] && [ ! -d "$ADDONS_DIR" ]; then
  exit 0
fi

# ── Progress Bar ──────────────────────────────────────────────────────────────
draw_progress() {
  local current=$1 total=$2 start=$3 label=$4
  local width=36
  [ "$total" -eq 0 ] && return
  local filled=$(( current * width / total ))
  local pct=$(( current * 100 / total ))
  local bar="" i=0
  while [ $i -lt $filled ]; do bar="${bar}█"; i=$((i+1)); done
  while [ $i -lt $width ];  do bar="${bar}░"; i=$((i+1)); done
  local eta_str=""
  local now; now=$(date +%s 2>/dev/null) || now=0
  if [ "$now" -gt 0 ] && [ "$current" -gt 0 ]; then
    local elapsed=$(( now - start ))
    if [ "$elapsed" -gt 0 ]; then
      local eta=$(( elapsed * (total - current) / current ))
      if   [ "$eta" -le 0 ];  then eta_str=" · done"
      elif [ "$eta" -lt 60 ]; then eta_str=" · ETA ${eta}s"
      else                         eta_str=" · ETA $((eta/60))m $((eta%60))s"
      fi
    fi
  fi
  printf "\r  %s  [%s] %3d%%  (%d/%d)%s" "$label" "$bar" "$pct" "$current" "$total" "$eta_str"
}

# ── Write a skill's cache entry (up to 5 content lines) ──────────────────────
write_skill_entry() {
  local skill_file="$1"
  local name="$2"
  local lines_written=0

  echo "### $name"

  # 1. Description from frontmatter (always line 1)
  local desc
  desc=$(grep -m1 '^description:' "$skill_file" 2>/dev/null \
         | sed 's/^description:[[:space:]]*//' | tr -d '"' | tr -d '\r' | cut -c1-300)
  if [ -n "$desc" ]; then
    echo "- **Use:** $desc"
    lines_written=$((lines_written + 1))
  fi

  # 2. Tags from frontmatter
  local tags
  tags=$(grep -m1 'tags:' "$skill_file" 2>/dev/null \
         | sed 's/.*tags:[[:space:]]*//' | tr -d '"' | tr -d '\r')
  if [ -n "$tags" ] && [ $lines_written -lt 5 ]; then
    echo "- **Tags:** $tags"
    lines_written=$((lines_written + 1))
  fi

  # Extract body (everything after the closing --- of frontmatter), strip \r
  local body
  body=$(awk 'BEGIN{n=0} /^---/{n++; if(n==2){p=1;next}} p{print}' "$skill_file" 2>/dev/null \
         | tr -d '\r')

  # 3. "## When to use" section — first non-empty, non-header line after that heading
  local when_line=""
  if [ $lines_written -lt 5 ]; then
    when_line=$(printf '%s\n' "$body" \
      | awk '/^## [Ww]hen [Tt]o [Uu]se/{p=1;next} /^#/{p=0}
             p && /[^[:space:]]/ && !/^\*\*Use for|^\*\*Skip|^Use for:|^Skip for:/{
               line=$0
               gsub(/^[[:space:]]+/, "", line)
               gsub(/^-[[:space:]]+/, "", line)
               print line; exit
             }' \
      | cut -c1-200)
    if [ -n "$when_line" ]; then
      echo "- **When:** $when_line"
      lines_written=$((lines_written + 1))
    fi
  fi

  # 4. "Use for:" / "TRIGGER when:" — inline content or first bullet beneath
  if [ $lines_written -lt 5 ]; then
    local use_line
    use_line=$(printf '%s\n' "$body" \
      | grep -m1 -E '^\*\*Use for|^Use for:|^TRIGGER when:|^Use this skill' \
      | sed 's/\*\*//g' \
      | sed 's/^Use for:[[:space:]]*//' \
      | sed 's/^TRIGGER when:[[:space:]]*//' \
      | sed 's/^Use this skills*[[:space:]]*//' \
      | sed 's/^[[:space:]]*//' \
      | cut -c1-200)
    # If empty or bare label, grab first bullet beneath the section
    if [ -z "$use_line" ]; then
      use_line=$(printf '%s\n' "$body" \
        | awk '/^\*\*Use for|^Use for:/{p=1;next} p && /^-[[:space:]]/{gsub(/^-[[:space:]]*/,""); print; exit} p && /^[^[:space:]-]/{exit}' \
        | cut -c1-200)
      [ -n "$use_line" ] && use_line="Use for: $use_line"
    fi
    # Skip if content overlaps with when_line (check both directions)
    if [ -n "$use_line" ]; then
      _skip=false
      case "$when_line" in *"$use_line"*) _skip=true ;; esac
      case "$use_line" in *"$when_line"*) _skip=true ;; esac
      if [ "$_skip" = false ]; then
        echo "- $use_line"
        lines_written=$((lines_written + 1))
      fi
    fi
  fi

  # 5. "Skip for:" / "SKIP:" — inline or first bullet beneath
  if [ $lines_written -lt 5 ]; then
    local skip_line
    skip_line=$(printf '%s\n' "$body" \
      | grep -m1 -Ei '^\*\*Skip for|^Skip for:|^SKIP:' \
      | sed 's/\*\*//g' \
      | sed 's/^Skip for:[[:space:]]*//' \
      | sed 's/^SKIP:[[:space:]]*//' \
      | sed 's/^[[:space:]]*//' \
      | cut -c1-200)
    if [ -z "$skip_line" ]; then
      skip_line=$(printf '%s\n' "$body" \
        | awk '/^\*\*Skip for|^Skip for:|^SKIP:/{p=1;next} p && /^-[[:space:]]/{gsub(/^-[[:space:]]*/,""); print; exit} p && /^[^[:space:]-]/{exit}' \
        | cut -c1-200)
    fi
    if [ -n "$skip_line" ]; then
      echo "- **Skip:** $skip_line"
    fi
  fi

  echo ""
}

# ── Write an add-on's cache entry ─────────────────────────────────────────────
write_addon_entry() {
  local addon_dir="$1"
  local name="$2"
  local readme="$addon_dir/README.md"

  echo "### $name"

  if [ -f "$readme" ]; then
    # Skip headings, badges, empty lines, HTML tags, and comments
    grep -Ev '^#|^!\[|^[[:space:]]*$|^\[!|^---|^[[:space:]]*<|^[[:space:]]*<!--' "$readme" 2>/dev/null \
      | tr -d '\r' \
      | sed 's/^[[:space:]>*-]*//' \
      | grep -Ev '^$|^&[a-z]' \
      | head -2 \
      | while IFS= read -r line; do
          echo "- $(echo "$line" | cut -c1-200)"
        done
  else
    echo "- No description available"
  fi

  echo ""
}

# ── Collect item paths (always runs) ─────────────────────────────────────────
skills_paths=""
skills_count=0
addons_paths=""
addons_count=0

if [ -d "$SKILLS_DIR" ]; then
  for d in "$SKILLS_DIR"/*/; do
    name=$(basename "$d")
    if [ "$name" != "skill-optimizer" ] && [ -f "$d/SKILL.md" ]; then
      skills_paths="$skills_paths|$d"
      skills_count=$((skills_count + 1))
    fi
  done
fi

if [ -d "$ADDONS_DIR" ]; then
  for d in "$ADDONS_DIR"/*/; do
    if [ -d "$d" ]; then
      addons_paths="$addons_paths|$d"
      addons_count=$((addons_count + 1))
    fi
  done
fi

total_items=$((skills_count + addons_count))

# ── Decide: full build, incremental update, or cache is current ───────────────
needs_full_build=false
new_skill_paths=""
new_addon_paths=""
new_count=0

if [ ! -f "$CACHE_FILE" ]; then
  needs_full_build=true
else
  if [ -n "$skills_paths" ]; then
    IFS='|' read -ra _arr <<< "$skills_paths"
    for d in "${_arr[@]}"; do
      [ -z "$d" ] && continue
      name=$(basename "$d")
      if ! grep -q "^### ${name}$" "$CACHE_FILE" 2>/dev/null; then
        new_skill_paths="$new_skill_paths|$d"
        new_count=$((new_count + 1))
      fi
    done
  fi
  if [ -n "$addons_paths" ]; then
    IFS='|' read -ra _arr <<< "$addons_paths"
    for d in "${_arr[@]}"; do
      [ -z "$d" ] && continue
      name=$(basename "$d")
      if ! grep -q "^### ${name}$" "$CACHE_FILE" 2>/dev/null; then
        new_addon_paths="$new_addon_paths|$d"
        new_count=$((new_count + 1))
      fi
    done
  fi
fi

# ── Full cache build ──────────────────────────────────────────────────────────
if $needs_full_build; then
  # Show header only on first-ever run; silent upgrade for returning projects
  if [ ! -f "$MARKER_FILE" ]; then
    echo ""
    echo "╔══════════════════════════════════════════════════════════╗"
    echo "║           SKILL OPTIMIZER — PROJECT START SCAN           ║"
    echo "╚══════════════════════════════════════════════════════════╝"
    echo ""
    echo "  Building skills cache for the first time..."
  else
    echo ""
    echo "  [skill-optimizer] Upgrading to v2 — building skills cache..."
  fi
  echo ""

  {
    echo "# Skill Optimizer Cache"
    echo "<!-- last-updated: $(date '+%Y-%m-%d') -->"
    echo ""
    echo "## Skills"
    echo ""
  } > "$CACHE_FILE"

  start_time=$(date +%s 2>/dev/null) || start_time=0
  processed=0

  if [ -n "$skills_paths" ]; then
    IFS='|' read -ra _arr <<< "$skills_paths"
    for d in "${_arr[@]}"; do
      [ -z "$d" ] && continue
      name=$(basename "$d")
      [ ! -f "$MARKER_FILE" ] && draw_progress "$processed" "$total_items" "$start_time" "Scanning"
      write_skill_entry "$d/SKILL.md" "$name" >> "$CACHE_FILE"
      processed=$((processed + 1))
    done
  fi

  { echo "## Add-Ons"; echo ""; } >> "$CACHE_FILE"

  if [ -n "$addons_paths" ]; then
    IFS='|' read -ra _arr <<< "$addons_paths"
    for d in "${_arr[@]}"; do
      [ -z "$d" ] && continue
      name=$(basename "$d")
      [ ! -f "$MARKER_FILE" ] && draw_progress "$processed" "$total_items" "$start_time" "Scanning"
      write_addon_entry "$d" "$name" >> "$CACHE_FILE"
      processed=$((processed + 1))
    done
  fi

  if [ ! -f "$MARKER_FILE" ]; then
    draw_progress "$total_items" "$total_items" "$start_time" "Scanning"
    echo ""
  fi
  echo ""
  echo "  Cache saved → $CACHE_FILE"

# ── Incremental update ────────────────────────────────────────────────────────
elif [ "$new_count" -gt 0 ]; then
  [ ! -f "$MARKER_FILE" ] && echo "" && echo "╔══════════════════════════════════════════════════════════╗" && echo "║           SKILL OPTIMIZER — PROJECT START SCAN           ║" && echo "╚══════════════════════════════════════════════════════════╝"
  echo ""
  echo "  Found $new_count new item(s) — updating cache..."
  echo ""

  start_time=$(date +%s 2>/dev/null) || start_time=0
  processed=0
  ENTRY_TMP="${CACHE_FILE}.entry"

  if [ -n "$new_skill_paths" ]; then
    IFS='|' read -ra _arr <<< "$new_skill_paths"
    for d in "${_arr[@]}"; do
      [ -z "$d" ] && continue
      name=$(basename "$d")
      draw_progress "$processed" "$new_count" "$start_time" "Updating"
      write_skill_entry "$d/SKILL.md" "$name" > "$ENTRY_TMP"
      awk 'FNR==NR{entry=entry $0 "\n"; next} /^## Add-Ons/{printf "%s\n", entry} {print}' \
        "$ENTRY_TMP" "$CACHE_FILE" > "${CACHE_FILE}.tmp" \
        && mv "${CACHE_FILE}.tmp" "$CACHE_FILE"
      processed=$((processed + 1))
    done
  fi

  if [ -n "$new_addon_paths" ]; then
    IFS='|' read -ra _arr <<< "$new_addon_paths"
    for d in "${_arr[@]}"; do
      [ -z "$d" ] && continue
      name=$(basename "$d")
      draw_progress "$processed" "$new_count" "$start_time" "Updating"
      write_addon_entry "$d" "$name" >> "$CACHE_FILE"
      processed=$((processed + 1))
    done
  fi

  rm -f "$ENTRY_TMP"
  sed -i "s|<!-- last-updated:.*-->|<!-- last-updated: $(date '+%Y-%m-%d') -->|" "$CACHE_FILE" 2>/dev/null
  draw_progress "$new_count" "$new_count" "$start_time" "Updating"
  echo ""
  echo ""
  echo "  Cache updated → $CACHE_FILE"
fi

# ── Mid-project: exit quietly if nothing changed, recommend if cache updated ──
if [ -f "$MARKER_FILE" ]; then
  if [ "$new_count" -eq 0 ] && ! $needs_full_build; then
    exit 0
  fi
  # New items were found — fall through to recommendations so Claude can
  # reassess relevance given the current project direction
  echo ""
  echo "  New skills added — reassessing recommendations for this project..."
fi

# ── First run: show header (if not already shown above), output recommendations
if ! $needs_full_build && [ "$new_count" -eq 0 ]; then
  echo ""
  echo "╔══════════════════════════════════════════════════════════╗"
  echo "║           SKILL OPTIMIZER — PROJECT START SCAN           ║"
  echo "╚══════════════════════════════════════════════════════════╝"
  echo ""
  echo "  Cache is up to date — no new skills or add-ons found."
fi

echo ""

# ── Output cache for Claude ───────────────────────────────────────────────────
echo "──────────────────────────────────────────────────────────────"
echo "SKILLS & ADD-ONS (from cache):"
echo ""
cat "$CACHE_FILE"
echo ""
echo "──────────────────────────────────────────────────────────────"
echo "[skill-optimizer] INSTRUCTIONS FOR CLAUDE:"
echo ""
if [ -f "$MARKER_FILE" ]; then
echo "This project is already in progress. New skills were just added to the cache."
echo "Do the following before responding:"
echo ""
echo "1. Review the full skills and add-ons list above."
echo "2. Assess the CURRENT state and direction of this project from conversation"
echo "   context — the project may have changed from its original concept."
echo "3. Reassess ALL skills/add-ons against the current direction (not just new ones)."
echo "   Flag any that are now relevant that weren't before, and any that no longer fit."
echo "4. For each relevant item state: name, why it fits the current project direction,"
echo "   and where/how it would be used from here."
echo "5. Ask the user: 'Would you like me to activate any of these?'"
echo "6. Wait for confirmation before proceeding."
else
echo "Before responding to the user's project idea, do the following:"
echo ""
echo "1. Review the skills and add-ons listed above (loaded from cache)."
echo "2. Based on the user's project idea, identify which are relevant."
echo "3. For each relevant item, state:"
echo "     - Name of the skill/add-on"
echo "     - Why it is relevant to this specific project"
echo "     - Where/how it would be used during the build"
echo "4. Ask the user: 'Would you like me to activate these for the project?'"
echo "5. Wait for confirmation before proceeding."
echo "6. After presenting your recommendations, create the file: $MARKER_FILE"
fi
echo "──────────────────────────────────────────────────────────────"
echo ""
