---
name: clickup-code-review:update
description: Force-update the clickup-code-review plugin cache and verify the installed version matches the marketplace. Use when skills are running with outdated code after a plugin update.
user_invocable: true
---

# ClickUp Code Review — Force Update

Forces the plugin cache to sync with the latest version from the marketplace.

## Problem This Solves

After updating the plugin via `/plugin` menu, the cache may still serve old skill files.
`/reload-plugins` reloads the plugin registry but does NOT refresh cached skill content.
A session restart is required for new skill content to load — this command verifies
that the cache is current and tells you if a restart is needed.

## Procedure

### Step 1: Detect Current State

```
1. Read the plugin.json from the SOURCE repo to get the latest version:
   Bash: echo $CLAUDE_PLUGIN_ROOT
   Read: {PLUGIN_ROOT}/.claude-plugin/plugin.json → extract "version"
   This is the INSTALLED version (what the cache has).

2. Check marketplace for the PUBLISHED version:
   Read the marketplace.json from the repo root (parent of plugin dir):
   The marketplace is at the repo root, not inside the plugin.
   Look for the clickup-code-review entry → extract "version"

3. Compare versions:
   - INSTALLED == PUBLISHED → cache is current
   - INSTALLED < PUBLISHED → cache is outdated
```

### Step 2: Verify Cache Content

Even if versions match, verify critical files have the expected content:

```
1. Check guard marker path (v5.2.6+ fix):
   Grep for "\.claude/code-reviews" in the INSTALLED skill files
   If found → cache has OLD content despite version match

2. Check code-reviews path:
   Grep for "code-reviews/" in audit SKILL.md
   Should find "code-reviews/" NOT ".claude/code-reviews/"

3. Report findings to user
```

### Step 3: Report & Action

```
IF cache is current AND content verified:
  "Plugin v{version} is current. Cache verified. No action needed."

IF cache is outdated OR content stale:
  "Plugin cache is outdated. Current: v{installed}, Latest: v{published}."
  "Actions needed:"
  "1. Run /plugin → select clickup-code-review → Update"
  "2. Run /reload-plugins"
  "3. Restart this session (/exit + re-open)"
  ""
  "Note: /reload-plugins alone is NOT sufficient — skills are loaded"
  "at session start and cached in memory. Only a session restart"
  "loads the new skill content."

IF old data exists at .claude/code-reviews/:
  "WARNING: Old review data found at .claude/code-reviews/"
  "This path was deprecated in v5.2.6. Move to code-reviews/:"
  "  mv .claude/code-reviews/* code-reviews/"
```
