---
description: Review staged changes with multiple specialized agents
allowed-tools: Bash(git diff:*), Bash(git status:*), Read, Grep, Glob, Task
---

# 🔍 Local Code Review: Staged Changes

## Current Staged Changes

```bash
!`git status --short`
```

**Detailed diff:**
```bash
!`git diff --cached --stat`
```

---

## Review Process

You will now launch **5 specialized agents IN PARALLEL** to review these staged changes independently:

1. **security-reviewer**: Security vulnerabilities (SQL injection, XSS, auth bypass, etc.)
2. **bug-detector**: Logic errors, off-by-one errors, null handling, edge cases
3. **performance-reviewer**: N+1 queries, missing indexes, caching opportunities
4. **quality-reviewer**: DRY violations, SOLID principles, code smells
5. **claude-md-compliance**: Project-specific CLAUDE.md convention violations

### Launch Agents

Use the Task tool to launch all 5 agents in parallel (single message, multiple tool calls):

```
Task(agent: security-reviewer, prompt: "Review the following staged changes for security vulnerabilities...")
Task(agent: bug-detector, prompt: "Review the following staged changes for bugs...")
Task(agent: performance-reviewer, prompt: "Review the following staged changes for performance issues...")
Task(agent: quality-reviewer, prompt: "Review the following staged changes for code quality issues...")
Task(agent: claude-md-compliance, prompt: "Review the following staged changes for CLAUDE.md convention violations...")
```

Provide each agent with:
- The full `git diff --cached` output
- Context about the project (Laravel/PHP, frameworks used)
- Instruction to report only issues with >=80% confidence

---

## Consolidation Phase

After all agents complete:

1. **Collect findings** from all 5 agents
2. **Filter by confidence** - only issues >=80%
3. **Remove duplicates** - if multiple agents report same issue, keep highest confidence
4. **Group by severity**:
   - **Critical**: Security vulnerabilities, data loss bugs
   - **Major**: Performance bottlenecks, significant bugs
   - **Minor**: Code quality, convention violations

---

## Final Report Format

```markdown
## 🔍 Local Code Review Report: Staged Changes

**Files reviewed:** X files
**Lines changed:** +X -X
**Agents used:** 5 (security, bugs, performance, quality, compliance)
**Execution time:** Xs

---

### ❌ Critical Issues (must fix before commit)

[If none: "✅ No critical issues found"]

- **[SECURITY-1] SQL Injection in UserController** - Confidence: 95%
  - File: `app/Http/Controllers/UserController.php:42`
  - Issue: Unparameterized SQL query with user input
  - Fix: Use Eloquent or prepared statements
  ```php
  // ❌ Vulnerable
  $users = DB::select("SELECT * FROM users WHERE email = '" . $request->email . "'");

  // ✅ Fixed
  $users = User::where('email', $request->email)->get();
  ```

---

### ⚠️ Major Issues (should fix)

[If none: "✅ No major issues found"]

- **[PERF-1] N+1 Query Problem** - Confidence: 90%
  - File: `app/Http/Controllers/PostController.php:28`
  - Issue: Loading posts in loop without eager loading
  - Fix: Add `->with('user')` to query
  ```php
  // ❌ N+1 (1 + N queries)
  foreach ($posts as $post) {
      echo $post->user->name;
  }

  // ✅ Fixed (2 queries)
  $posts = Post::with('user')->get();
  ```

---

### ℹ️ Minor Issues (consider fixing)

[If none: "✅ No minor issues found"]

- **[QUALITY-1] Fat Controller** - Confidence: 85%
  - File: `app/Http/Controllers/OrderController.php:15`
  - Issue: Controller method has 65 lines of business logic
  - Fix: Extract to OrderService

---

## Summary

- **Total issues found:** X
  - Critical: X
  - Major: X
  - Minor: X

**Recommendation:**
- ✅ **Safe to commit** - No critical or major issues
- ⚠️ **Fix critical issues first** - X critical issues must be resolved
- ❌ **Do not commit** - X critical issues + X major issues

---

## Next Steps

Based on this review:
1. If critical issues: Fix them before committing
2. If major issues: Consider fixing before committing
3. If only minor issues: Safe to commit, but consider fixing later
4. If no issues: Ready to commit!
```

---

## Important Notes

- **Confidence threshold:** Only report issues with >=80% confidence
- **No false positives:** Agents are instructed to be conservative
- **Context matters:** Agents understand Laravel/PHP conventions
- **Actionable feedback:** Every issue includes specific fix
