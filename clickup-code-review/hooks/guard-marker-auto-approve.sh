#!/bin/bash
# ClickUp Code Review Plugin — Guard Marker Auto-Approve
# Hook: PreToolUse (matcher: Bash)
#
# PURPOSE: Auto-approve touch/rm of the session guard marker file.
# This hook has NO guard check itself (it IS the guard lifecycle).
# Runs globally — always active, regardless of skill session state.
#
# Only approves:
#   mkdir -p code-reviews
#   touch code-reviews/.clickup-review-active
#
# INTENCIONALMENTE NAO aprova 'rm -f code-reviews/.clickup-review-active':
# o rm sinaliza o FIM de uma skill (ou um bypass manual do PreCompact guard).
# Manter prompt manual aqui da visibilidade ao utilizador sempre que o marker
# e removido — essencial para detectar prompt injection que tente contornar
# o bloqueio de compactacao (ver hooks/precompact-guard.sh). Custo: 1 prompt
# no fim de cada skill (audit/planning/fix/testing), ~4 por workflow completo.

exec 2>/dev/null

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)

if echo "$command" | grep -qE '^mkdir -p code-reviews$'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
fi

if echo "$command" | grep -qE 'touch [^ ]*code-reviews/\.clickup-review-active'; then
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
fi

# No match → no opinion (fall through to other hooks / manual approval)
exit 0
