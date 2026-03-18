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
# Without this hook, a typical planning session with 4 tickets generates
# ~28 permission prompts for Agent spawns, SendMessage, TeamCreate/Delete.
#
# INSTALLED BY: Plugin hooks/hooks.json (auto-loaded when plugin is enabled)

# Read stdin (tool input JSON from Claude Code)
input=$(cat)

# Extract tool name for logging (optional, can be removed for performance)
tool_name=$(echo "$input" | jq -r '.tool_name // ""' 2>/dev/null)

# Auto-approve all orchestration tools
# These tools only coordinate agents — they don't modify files or run commands
echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
exit 0
