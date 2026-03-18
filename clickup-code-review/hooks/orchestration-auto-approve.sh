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

# Consume stdin (required by hook protocol)
cat > /dev/null

# Auto-approve all orchestration tools
echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
exit 0
