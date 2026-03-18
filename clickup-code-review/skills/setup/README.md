# Setup Skill — `/clickup-code-review:setup`

Interactive configuration wizard for the ClickUp Code Review plugin. Guides the user through token setup, workspace navigation, and permission pre-authorization.

## Pipeline Position

```
/clickup-code-review:setup     ←  THIS SKILL (run first or when reconfiguring)
/clickup-code-review           →  Audit
/clickup-code-review:planning  →  Planning
/clickup-code-review:fix       →  Fixing
```

**Run this first** or whenever you need to reconfigure. Each of the other 3 skills auto-triggers setup if configuration is missing.

## What It Configures

| Step | What | Where Stored |
|------|------|-------------|
| 1 | Detect Claude installation (CLDP/CLDW) | Session variable |
| 2 | ClickUp API Token (`pk_*`) | `settings.json` → `env.CLICKUP_API_TOKEN` |
| 3 | Workspace → Space → Folder → List | Project MEMORY.md |
| 4 | Project shortname (e.g., FSL) | Project MEMORY.md |
| 5 | Permission pre-authorization (18 operations) | `settings.json` → `permissions.allow` |
| 6 | Auto-approve hook for multi-statement scripts | `settings.json` → `hooks.PreToolUse` |
| 7 | Local cache gitignore check | Project `.gitignore` |

## Key Features

- **Always confirms** — Even if config exists, shows current values for user confirmation
- **CLDP/CLDW detection** — Checks `~/.claude-personal/settings.json` (CLDP) and `~/.claude/settings.json` (CLDW)
- **Per-project override** — Option to use different config for specific projects
- **Granular permissions** — 18 operations across 5 categories, each individually selectable
- **Active state indicators** — Shows which permissions are currently active during reconfiguration

## References

- `references/clickup-api-patterns.md` — Shared API patterns (plugin root)
