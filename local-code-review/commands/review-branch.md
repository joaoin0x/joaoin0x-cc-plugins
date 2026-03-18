---
description: Review all commits in current branch not yet merged to target branch
argument-hint: <base-branch>
allowed-tools: Bash(git diff:*), Bash(git log:*), Bash(git branch:*), Read, Grep, Glob, Task
---

# 🔍 Local Code Review: Branch vs Base

## Validation

**Target base branch:** `$1`

```bash
!`if [ -z "$1" ]; then echo "❌ ERROR: Base branch argument required"; echo ""; echo "Usage: /local-code-review:review-branch <base-branch>"; echo ""; echo "Examples:"; echo "  /local-code-review:review-branch devmaster"; echo "  /local-code-review:review-branch staging"; echo "  /local-code-review:review-branch production"; exit 1; fi; if ! git show-ref --verify --quiet refs/heads/$1; then echo "❌ ERROR: Branch '$1' does not exist"; echo ""; echo "Available branches:"; git branch -a | grep -v HEAD; exit 1; fi; echo "✅ Base branch '$1' exists"`
```

## Current Branch

```bash
!`git branch --show-current`
```

## Commits Not Merged

**Commits in current branch not in `$1`:**
```bash
!`git log $1..HEAD --oneline`
```

**Commit count:**
```bash
!`git rev-list --count $1..HEAD`
```

## Total Changes

**Changed files:**
```bash
!`git diff $1...HEAD --stat`
```

**Lines changed:**
```bash
!`git diff $1...HEAD --shortstat`
```

---

## Review Process

Launch **5 specialized agents IN PARALLEL** to review all changes before merging to **`$1`**:

1. **security-reviewer**: Security vulnerabilities
2. **bug-detector**: Logic errors and bugs
3. **performance-reviewer**: Performance issues
4. **quality-reviewer**: Code quality
5. **claude-md-compliance**: CLAUDE.md compliance

### Instructions for Agents

Provide each agent with the complete diff:
```bash
git diff $1...HEAD
```

**Context for agents:**
- **Current branch:** [from git branch --show-current]
- **Target branch:** `$1`
- **Purpose:** Review all commits before merge
- **Scope:** All changes since branch diverged from `$1`

---

## Final Report

Consolidate findings:
- Filter by confidence >=80%
- Remove duplicates
- Group by severity

**Purpose:** Review entire branch before creating PR or merging.

---

## Next Steps

**Before merging to `$1`:**

1. **Fix critical issues** - Must be resolved before merge
2. **Fix major issues** - Should be resolved (or document why not)
3. **Consider minor issues** - Improve over time
4. **Run all tests** - Ensure everything passes
5. **Merge when clean:**
   ```bash
   git checkout $1
   git merge [current-branch]
   ```

**Purpose:** Comprehensive review before merge to catch issues early in the development workflow.
