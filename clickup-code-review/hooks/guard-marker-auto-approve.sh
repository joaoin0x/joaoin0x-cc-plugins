#!/bin/bash
# ClickUp Code Review Plugin — Guard Marker Auto-Approve
# Hook: PreToolUse (matcher: Bash)
#
# PURPOSE: Auto-approve touch/rm of the session guard marker file.
# This hook has NO guard check itself (it IS the guard lifecycle).
# Runs globally — always active, regardless of skill session state.
#
# Only approves:
#   touch $CLAUDE_PROJECT_DIR/.claude/code-reviews/.clickup-review-active
#   rm -f $CLAUDE_PROJECT_DIR/.claude/code-reviews/.clickup-review-active

exec 2>/dev/null

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)

if echo "$command" | grep -qE '^touch [^ ]*\.claude/code-reviews/\.clickup-review-active$'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
fi

if echo "$command" | grep -qE '^rm -f [^ ]*\.claude/code-reviews/\.clickup-review-active$'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
fi

# No match → no opinion (fall through to other hooks / manual approval)
exit 0
