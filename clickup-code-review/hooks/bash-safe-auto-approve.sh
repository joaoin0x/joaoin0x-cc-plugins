#!/bin/bash
# ClickUp Code Review Plugin — Bash Safe Auto-Approve Hook
# Hook: PreToolUse (matcher: Bash)
#
# PURPOSE: Auto-approve safe, single-statement Bash commands.
# Auto-deny dangerous or multi-statement commands (no user prompt).
# Prevents overnight session blocks from routine git/test commands.
#
# SECURITY MODEL:
# 1. DENY LIST checked FIRST — matches emit auto-deny (agent gets rejection, no prompt)
# 2. WHITELIST checked second — matches emit allow
# 3. No match → fall through to manual approval (safe by default)
#
# RULE: ONLY single-statement commands are approved.
# Any command with &&, ||, or ; is AUTO-DENIED (agent must retry with single-statement).
#
# INSTALLED BY: Plugin hooks/hooks.json (auto-loaded when plugin is enabled)

input=$(cat)
command=$(echo "$input" | jq -r '.tool_input.command // ""' 2>/dev/null)

# Helper: emit auto-deny with reason (agent gets rejection, NO user prompt)
deny() {
    printf '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"deny","reason":"%s"}}\n' "$1"
    exit 0
}

# Helper: emit auto-allow
allow() {
    echo '{"hookSpecificOutput":{"hookEventName":"PreToolUse","permissionDecision":"allow"}}'
    exit 0
}

# === EARLY WHITELIST (before deny list — safe commands that contain deny-list patterns) ===

# Git commit single-line: approved early because heredoc/substitution patterns in commit
# messages would trigger deny checks. --no-verify/--amend still denied.
if echo "$command" | grep -qE '^git commit -m '; then
    if echo "$command" | grep -qE '(--no-verify|--amend)'; then
        deny "git commit --no-verify/--amend proibido."
    fi
    allow
fi

# === DENY LIST (checked FIRST — auto-denied, no user prompt) ===

# Chained commands: && || ; (logical operators and statement separators)
# NOTE: Single pipe | is NOT denied here (read-only pipes are whitelisted below)
if echo "$command" | grep -qE '&&|;'; then
    deny "Comandos encadeados proibidos. Usar single-statement Bash."
fi

# Logical OR || (must be separate from pipe | detection)
if echo "$command" | grep -qE '\|\|'; then
    deny "Comandos encadeados proibidos. Usar single-statement Bash."
fi

# Multi-line commands (newline as statement separator — bypasses ; check above)
# printf '%s' avoids adding trailing newline; wc -l counts only embedded newlines
if [ "$(printf '%s' "$command" | wc -l)" -gt 0 ]; then
    deny "Comandos multi-linha proibidos. Usar single-statement Bash."
fi

# ANSI-C quoting ($'...') can encode newlines/null bytes silently
if printf '%s' "$command" | grep -qF '$'"'"; then
    deny "ANSI-C quoting proibido. Usar single-statement Bash."
fi

# Heredoc operators (can wrap multi-statement commands)
if echo "$command" | grep -qE '<<'; then
    deny "Heredocs proibidos. Usar Write TOOL para ficheiros, single-statement curl."
fi

# Pipe to shell interpreter (with or without space before pipe: cmd|bash or cmd | bash)
if echo "$command" | grep -qE '\| *(sh|bash|zsh|fish)( |$)'; then
    deny "Pipe para shell proibido. Usar single-statement Bash."
fi

# Process substitution: <(cmd) or >(cmd) — executes subcommands
if echo "$command" | grep -qE '[<>]\('; then
    deny "Process substitution proibido. Usar single-statement Bash."
fi

# Command substitution: $(cmd) or `cmd` — injects subcommands into whitelisted prefixes
# Exception: VARIABLE=$(curl ...) is safe (API response capture, used by CU Manager)
if echo "$command" | grep -qE '\$\(|`'; then
    if ! echo "$command" | grep -qE '^[A-Z_]+=\$\(curl '; then
        deny "Command substitution proibido. Usar single-statement Bash."
    fi
fi

# Destructive git operations
if echo "$command" | grep -qE '^git (push|reset --hard|reset --mixed|reset --soft|clean -|rebase)'; then
    deny "Operacao git destrutiva proibida."
fi

# git checkout -- / git switch --discard-changes (destroys unstaged changes — irreversible)
# Also deny force-branch-create: -B (checkout), -C (switch), -f force
if echo "$command" | grep -qE '^git (checkout|switch) .*(--|--discard-changes|--force|-[fBFC])( |$)'; then
    deny "git checkout/switch destrutivo proibido."
fi

# git commit --no-verify (bypasses pre-commit hooks) or --amend (rewrites history)
if echo "$command" | grep -qE '^git commit.*(--no-verify|--amend)'; then
    deny "git commit --no-verify/--amend proibido."
fi

# git add . / git add -A / glob * (too broad — must specify files)
# Also deny -p/-e/-i (interactive/editor modes — require TTY, would hang session)
if echo "$command" | grep -qE '^git add (\.|--all|-A|\*|-p|-e|-i)($| )'; then
    deny "git add generico proibido. Especificar ficheiros individualmente."
fi

# Destructive filesystem
if echo "$command" | grep -qE '(^| )rm -[rRf]'; then
    deny "rm recursivo/force proibido."
fi

# Destructive database
if echo "$command" | grep -qiE 'migrate:(fresh|reset)|db:wipe|DROP TABLE|TRUNCATE TABLE'; then
    deny "Operacao destrutiva de BD proibida."
fi

# Dangerous permissions / execution
if echo "$command" | grep -qE '(^| )(chmod 777|eval |source |exec )'; then
    deny "chmod 777/eval/source/exec proibidos."
fi

# Package installation (changes dependencies)
if echo "$command" | grep -qE '^(npm install|composer require|pip install|yarn add|pnpm add)'; then
    deny "Instalacao de packages proibida."
fi

# find with -exec/-delete/-ok (arbitrary command execution — NOT read-only)
if echo "$command" | grep -qE '^find .*(-exec |-ok |-delete)'; then
    deny "find com -exec/-delete proibido. Usar Glob TOOL."
fi

# === WHITELIST (single-statement only, deny list already passed) ===

# Git read-only operations (with optional -C path prefix)
if echo "$command" | grep -qE '^git (-C [^ ]+ )?(status|diff|log|branch|show|rev-parse|stash list|ls-files|shortlog)'; then
    allow
fi

# Git diff staged (with optional -C path prefix)
if echo "$command" | grep -qE '^git (-C [^ ]+ )?diff --staged'; then
    allow
fi

# Git add specific files (not . or -A, already denied above; with optional -C)
if echo "$command" | grep -qE '^git (-C [^ ]+ )?add '; then
    allow
fi

# Git commit (with optional -C path prefix; --no-verify/--amend caught in early whitelist)
if echo "$command" | grep -qE '^git (-C [^ ]+ )?commit'; then
    allow
fi

# Git branch creation / checkout existing (with optional -C path prefix)
if echo "$command" | grep -qE '^git (-C [^ ]+ )?(checkout|switch)'; then
    allow
fi

# Safe pipe patterns: git read-only | filter tool (pipe already passed deny list)
if echo "$command" | grep -qE '^git (-C [^ ]+ )?(log|diff|show|branch|ls-files|shortlog|status|rev-parse) .+\| *(grep|head|tail|wc|sort|uniq|cut|awk) '; then
    allow
fi

# Test suite runners
if echo "$command" | grep -qE '^(sail artisan test|php artisan test|./vendor/bin/phpunit|./vendor/bin/pest|vendor/bin/phpunit|vendor/bin/pest)'; then
    allow
fi

# Safe read-only commands (find only approved without -exec/-delete)
if echo "$command" | grep -qE '^(grep |cat |head |tail |wc |ls |find |printenv |date |stat )'; then
    allow
fi

# Environment variable check (single printenv without flags)
if echo "$command" | grep -qE '^printenv [A-Z_]+$'; then
    allow
fi

# Directory creation
if echo "$command" | grep -qE '^mkdir -p '; then
    allow
fi

# curl API calls (CU Manager needs these — already single-statement at this point)
if echo "$command" | grep -qE '^(curl |RESPONSE=\$\(curl )'; then
    allow
fi

# echo with variable (extracting API response data — safe read-only)
if echo "$command" | grep -qE '^echo "\$'; then
    allow
fi

# rm single file (cleanup of api-payload.json — NOT recursive, already denied rm -rf above)
if echo "$command" | grep -qE '^rm "[^"]*api-payload\.json"$'; then
    allow
fi

# No match → fall through to manual approval (safe by default)
# This only triggers for commands not in deny list AND not in whitelist.
# Examples: curl, echo, arbitrary commands not explicitly categorized.
exit 0
