#!/bin/bash
# ClickUp Code Review Plugin — File Operations Auto-Approve Hook
# Hook: PreToolUse (matcher: Write|Edit|Read)
#
# PURPOSE: Auto-approve file operations for:
#   - Read: ALL files except sensitive paths (.env, .ssh/, credentials, keys)
#   - Write/Edit: Plugin cache (code-reviews/) + safe source extensions
#
# SECURITY:
# - Sensitive files always fall through to manual approval
# - Destructive config files (composer.json, package.json root, .gitignore root) fall through
# - Everything else is safe to auto-approve for plugin workflow
#
# INSTALLED BY: Plugin hooks/hooks.json (auto-loaded when plugin is enabled)
#
# GUARD: Only active during plugin skill sessions.

# Suppress stderr — prevents hook runner from interpreting errors as hook failures
exec 2>/dev/null

GUARD="$CLAUDE_PROJECT_DIR/code-reviews/.clickup-review-active"
if [ -f "$GUARD" ]; then
    age=$(($(date +%s) - $(stat -f '%m' "$GUARD")))
    if [ "$age" -gt 14400 ]; then
        rm -f "$GUARD"
    fi
fi
if [ ! -f "$GUARD" ]; then
    cat > /dev/null
    exit 0
fi

input=$(cat)

# Extract tool name and file path
tool_name=$(echo "$input" | jq -r '.tool_name // ""' 2>/dev/null)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // ""' 2>/dev/null)

# === SENSITIVE PATH DENY LIST (applies to ALL tools) ===
# These always fall through to manual regardless of tool

if echo "$file_path" | grep -qE '(^|/)\.env'; then
    exit 0
fi

if echo "$file_path" | grep -qE '(^|/)\.ssh/'; then
    exit 0
fi

if echo "$file_path" | grep -qiE '(credentials|\.key$|\.pem$|\.p12$|\.pfx$|id_rsa|id_ed25519)'; then
    exit 0
fi

# === READ: Auto-approve all non-sensitive reads ===
if [ "$tool_name" = "Read" ]; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
fi

# === WRITE / EDIT ===

# Always approve plugin cache directory
if echo "$file_path" | grep -qE '\code-reviews/'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
fi

# Always approve plugin own files
if echo "$file_path" | grep -qE '\.claude-personal/my-plugins/clickup-code-review/'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
fi

# Sensitive config files — fall through (require manual approval)
# .gitignore at project root
if echo "$file_path" | grep -qE '^\.gitignore$|/\.gitignore$'; then
    exit 0
fi

# Root-level composer.json / package.json (dependency changes)
if echo "$file_path" | grep -qE '^(composer|package)\.json$'; then
    exit 0
fi

# Approve safe source extensions for specialist fixes
if echo "$file_path" | grep -qE '\.(php|blade\.php|js|ts|tsx|jsx|vue|css|scss|sass|json|yaml|yml|md|html|htm|xml|svg|txt)$'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
fi

# Not a recognised safe path — fall through to manual approval
exit 0
