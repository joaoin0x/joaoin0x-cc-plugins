#!/bin/bash
# ClickUp Code Review Plugin — Multi-Agent Orchestration Auto-Approve Hook
# Hook: PreToolUse (matcher: Agent|SendMessage|TeamCreate|TeamDelete)
#
# PURPOSE: Auto-approve multi-agent orchestration tools during plugin skills
# (audit, planning, fix, testing) to prevent permission prompt floods.
#
# SECURITY: This hook ONLY approves orchestration tools. It does NOT approve
# Bash, Write, Read, or any other tool that could modify files or run commands.
# Those are handled by separate hooks with path-based filtering.
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

# Consume stdin (required by hook protocol)
cat > /dev/null

# Auto-approve all orchestration tools
echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
exit 0
