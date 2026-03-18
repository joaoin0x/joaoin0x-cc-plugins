---
description: Review unstaged changes with multiple specialized agents
allowed-tools: Bash(git diff:*), Bash(git status:*), Read, Grep, Glob, Task
---

# 🔍 Local Code Review: Unstaged Changes

## Current Unstaged Changes

```bash
!`git status --short`
```

**Detailed diff:**
```bash
!`git diff --stat`
```

---

## Review Process

You will now launch **5 specialized agents IN PARALLEL** to review these unstaged changes independently:

1. **security-reviewer**: Security vulnerabilities
2. **bug-detector**: Logic errors and bugs
3. **performance-reviewer**: Performance issues and bottlenecks
4. **quality-reviewer**: Code quality and maintainability
5. **claude-md-compliance**: CLAUDE.md convention violations

### Launch Agents

Use the Task tool to launch all 5 agents in parallel with the full `git diff` output (unstaged changes).

---

## Final Report

Consolidate findings from all agents:
- Filter by confidence >=80%
- Remove duplicates
- Group by severity (Critical > Major > Minor)
- Provide actionable fixes

**Report format:** Same as review-staged.md

---

## Next Steps

1. Fix critical/major issues in working directory
2. Stage the fixes: `git add .`
3. Run `/local-code-review:review-staged` again
4. Commit when clean
