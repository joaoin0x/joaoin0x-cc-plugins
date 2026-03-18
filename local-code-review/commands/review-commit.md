---
description: Review a specific commit with multiple specialized agents
argument-hint: [commit-hash]
allowed-tools: Bash(git show:*), Bash(git log:*), Read, Grep, Glob, Task
---

# 🔍 Local Code Review: Specific Commit

## Commit to Review

Commit hash: **$1**

```bash
!`git show $1 --stat`
```

**Commit message:**
```bash
!`git log -1 --pretty=format:"%h - %an, %ar : %s" $1`
```

**Full diff:**
```bash
!`git show $1`
```

---

## Review Process

Launch **5 specialized agents IN PARALLEL** to review this commit:

1. **security-reviewer**: Security vulnerabilities
2. **bug-detector**: Logic errors and bugs
3. **performance-reviewer**: Performance issues
4. **quality-reviewer**: Code quality
5. **claude-md-compliance**: CLAUDE.md compliance

---

## Final Report

Consolidate findings:
- Filter by confidence >=80%
- Remove duplicates
- Group by severity

**Purpose:** Learn from past commits. Was this change good? What could be improved?

---

## Next Steps

If issues found:
1. Consider creating a follow-up commit to fix them
2. Learn for future commits
3. Update conventions if needed
