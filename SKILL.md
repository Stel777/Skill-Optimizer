---
name: skill-optimizer
description: Automatically scans available skills and add-ons at the start of each project and recommends relevant ones based on the project idea. Runs once per project directory.
user-invocable: true
allowed-tools: "Read Glob Bash"
hooks:
  UserPromptSubmit:
    - hooks:
        - type: command
          command: "bash \"${CLAUDE_PLUGIN_ROOT:-$HOME/.claude/skills/skill-optimizer}/scan.sh\" 2>/dev/null"
metadata:
  version: "2.1.0"
  author: "Stel"
  github: "https://github.com/Stel777/Skill-Optimizer"
---

# Skill Optimizer by Stel

Scans your available Claude skills and add-ons at the start of a new project, then recommends which ones are relevant — explaining where and why they'd be used — before building begins.

## How It Works

1. **Auto-runs** on your first prompt in any project directory (via a `UserPromptSubmit` hook)
2. **Scans** your skills folder and add-ons folder
3. **Analyzes** the project idea you described
4. **Recommends** relevant tools with clear explanations
5. **Asks for confirmation** before proceeding
6. **Creates `.skill-optimizer-ran`** in the project directory to avoid re-running

> To re-run the scan in the same project, delete `.skill-optimizer-ran` and submit a new prompt.

## Configuration

By default, the skill looks for:

| Folder | Default Path |
|--------|-------------|
| Skills | `~/.claude/skills/` |
| Add-Ons | `~/Documents/Claude_Stuff/Add-Ons/` |

To use different paths, set these environment variables (add to your shell profile):

```bash
export SKILL_OPTIMIZER_SKILLS_DIR="/path/to/your/skills"
export SKILL_OPTIMIZER_ADDONS_DIR="/path/to/your/addons"
```

## Manual Invocation

You can call this skill manually at any time:

```
/skill-optimizer
```

### Mid-Project Status Update

When invoked manually during an active project:

1. **Read the cache file** at `~/.claude/skill-optimizer-cache.md` — this is the source of truth for what skills and add-ons are available. If the cache doesn't exist (project predates v2), fall back to session memory.
2. **Report what's active** — which skills and add-ons from the cache have been used or loaded in this session, and where/why
3. **Report what's available but unused** — skills/add-ons in the cache that haven't been activated yet, with a note on whether they could still be helpful given the current project context
4. **Ask** if the user wants to activate anything they've missed

This gives you a clear, accurate picture of your full tool stack mid-build without triggering any re-scanning.

## Setup

### Option 1: Clone from GitHub

```bash
git clone https://github.com/Stel777/Skill-Optimizer ~/.claude/skills/skill-optimizer
```

### Option 2: Manual Install

1. Copy this folder to `~/.claude/skills/skill-optimizer/`
2. Make the scan script executable:
   ```bash
   chmod +x ~/.claude/skills/skill-optimizer/scan.sh
   ```
3. (Optional) Set environment variables for custom paths

### Requirements

- Claude Code CLI
- Bash (available on Mac, Linux, and Windows via Git Bash / WSL)

## For Skill Authors

For your skill to be discovered by Skill Optimizer, make sure your `SKILL.md` has a `description:` field in the frontmatter:

```yaml
---
name: my-skill
description: A short description of what this skill does and when to use it.
---
```

## What Gets Scanned

- **Skills:** Any subfolder in your skills directory that contains a `SKILL.md` file
- **Add-Ons:** Any subfolder in your add-ons directory (reads first line of `README.md` for description)

The skill-optimizer itself is excluded from its own scan results.
