#!/bin/bash
# ClickUp API Auto-Approve Hook (bundled with clickup-code-review plugin)
# Plugin-Version: 5.1.1
# Hook: PreToolUse (matcher: Bash)
#
# PURPOSE: Bridge the gap between multi-statement Bash scripts and the
# Bash(curl *) permission patterns, which only match single-command scripts.
#
# HOW IT WORKS:
# 1. Extracts the HTTP method (-X GET/POST/PUT/DELETE) from the curl command
# 2. Extracts the ClickUp API path from the URL
# 3. Reads the SAME permissions.allow from settings.json (configured by setup wizard)
# 4. Only approves if METHOD + URL matches an existing Bash(curl ...) permission
# 5. Falls through to manual approval for anything not in the list
#
# SECURITY: This hook does NOT approve arbitrary ClickUp calls.
# It enforces the exact same permissions the user chose during /clickup-code-review:setup.
# Source of truth: settings.json → permissions.allow
#
# INSTALLED BY: /clickup-code-review:setup (Step 6)
# The setup wizard sets SETTINGS_PATH below during installation.
#
# NOTE: jq is safe here — parsing Claude Code JSON and settings.json,
# NOT ClickUp API responses (which contain control characters that break jq).
# The "never use jq" rule applies ONLY to ClickUp API response parsing.

# ── CONFIGURED BY SETUP WIZARD ──────────────────────────────────────
# This path is set by the setup wizard. Do not change manually.
SETTINGS_PATH="__SETTINGS_PATH__"
# ─────────────────────────────────────────────────────────────────────

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""')

# Auto-approve local file operations for .claude/code-reviews/ (project-scoped)
# v5.0.3: /tmp/findings/ eliminated — all files under .claude/code-reviews/
if echo "$command" | grep -qE '(cat|tee|mkdir|echo|sed|date).*(\./\.claude/code-reviews/|\.claude/code-reviews/)'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
fi

# Quick exit: only process commands containing ClickUp API URLs
echo "$command" | grep -q "api\.clickup\.com" || exit 0

# Extract the HTTP method used in the curl command
METHOD=$(echo "$command" | grep -oE '\-X (GET|POST|PUT|DELETE)' | head -1 | awk '{print $2}')
[ -z "$METHOD" ] && exit 0

# Extract the ClickUp API path from the URL
API_PATH=$(echo "$command" | grep -oE 'api\.clickup\.com/api/v[23]/[^"[:space:]]+' | head -1)
[ -z "$API_PATH" ] && exit 0

# Use configured settings path (set by setup wizard)
[ -f "$SETTINGS_PATH" ] || exit 0

# Check each Bash(curl ...) permission that references ClickUp
# Match the extracted METHOD and API_PATH against allowed patterns
#
# Supported operations (configured via /clickup-code-review:setup):
#
# --- CREATE/UPDATE TICKETS ---
# curl *-X POST*api.clickup.com/api/v2/list/*/task*
# curl *-X PUT*api.clickup.com/api/v2/task/*
#
# --- STATUS CHANGES ---
# curl *-X PUT*api.clickup.com/api/v2/task/* (status in body)
#
# --- COMMENTS ---
# curl *-X GET*api.clickup.com/api/v2/task/*/comment*
# curl *-X POST*api.clickup.com/api/v2/task/*/comment*
#
# --- HIERARCHY/LISTS ---
# curl *-X GET*api.clickup.com/api/v2/list/*
# curl *-X GET*api.clickup.com/api/v2/team*
#
# --- DEPENDENCIES (v5.0: cascade blocking in QA) ---
# curl *-X POST*api.clickup.com/api/v2/task/*/dependency*
# curl *-X DELETE*api.clickup.com/api/v2/task/*/dependency*
#
# --- EVIDENCE GATES (v5.0: commit SHA verification) ---
# git log*--grep* (handled by settings.json permissions, not this hook)
#
while IFS= read -r perm; do
    # Extract method from permission pattern: *-X GET* → GET
    PERM_METHOD=$(echo "$perm" | grep -oE '\-X (GET|POST|PUT|DELETE)' | awk '{print $2}')
    [ "$METHOD" != "$PERM_METHOD" ] && continue

    # Extract URL pattern: *api.clickup.com/api/v2/list/*) → api.clickup.com/api/v2/list/
    PERM_URL=$(echo "$perm" | grep -oE 'api\.clickup\.com/api/v[23]/[^)]*' | sed 's/\*$//')
    [ -z "$PERM_URL" ] && continue

    # Check if the actual API path starts with the allowed pattern
    if echo "$API_PATH" | grep -q "^${PERM_URL}"; then
        echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
        exit 0
    fi
done < <(jq -r '.permissions.allow[]' "$SETTINGS_PATH" 2>/dev/null | grep "api\.clickup\.com")

# Not matched — fall through to manual approval
exit 0
