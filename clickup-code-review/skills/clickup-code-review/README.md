# Audit Skill — `/clickup-code-review`

Multi-agent code review that audits the entire codebase and creates ClickUp tickets for approved findings.

## Pipeline Position

```
/clickup-code-review           ←  THIS SKILL (creates tickets at "open")
/clickup-code-review:planning  →  Triage (open → planning → ready for dev)
/clickup-code-review:fix       →  Execute (ready for dev → deploy to staging)
```

**This is the FIRST step.** Run this before planning or fixing.

## How It Works

1. **Phase 0** — Configuration check (token, list ID, shortname). Gitignore check for `.claude/code-reviews/`
2. **Phase 1** — Create main task + ALL area subtasks upfront in ClickUp. **Create local folder tree** (`.claude/code-reviews/`) with `_main.md` + `_area.md` files
3. **Phase 2** — Spawn 7 specialist agents in parallel across selected areas
4. **Phase 3** — Devil's Advocate (opus) filters findings with streaming verdicts
5. **Phase 4** — Security verification pass (conditional — only if DA reports coverage gaps)
6. **Phase 5** — Create ClickUp tickets: POST name → **create local `.md` file** → compose description locally → PUT to ClickUp → update frontmatter
7. **Phase 6** — Data-driven summary (query ClickUp, never from memory)

## Agent Team

| Agent | Model | Subagent Type | Area |
|-------|-------|---------------|------|
| Security | opus | cybersecurity-expert | Vulnerabilities, auth, IDOR |
| Backend/Perf | sonnet | backend-architect | N+1, caching, queries |
| Frontend | sonnet | frontend-expert | WCAG, Blade, Bootstrap |
| Quality | sonnet | backend-architect | PSR-12, SOLID, dead code |
| Complexity | sonnet | clickup-code-review:code-simplifier | God classes, over-engineering |
| QA Unit | sonnet | qa-testing-expert | Test coverage gaps |
| QA E2E | sonnet | qa-testing-expert | Browser testing gaps |
| Devil's Advocate | opus | clickup-code-review:devils-advocate | Skeptical filtering (FINDING-FILTER mode) |

## Key Features

- **Local file cache** — Every ticket has a local `.md` file in `.claude/code-reviews/` with YAML frontmatter. Serves as composition surface, fallback, and persistent state.
- **Folder tree upfront** — Main folder + all area subfolders created at start. Empty folders = no findings (good sign).
- **Markdown checklists** — `- [ ]` in description renders as interactive checkboxes in ClickUp (zero extra API calls)
- **PT-PT language** — All narrative text in Português de Portugal, technical terms inline in English
- **Idempotency** — Fuzzy matching prevents duplicate tickets on re-run
- **2-step ticket creation** — POST name (get task_id) → create local `.md` → compose description → PUT to ClickUp. No GET round-trip.
- **Anti-hallucination** — Summary built from ClickUp query, not from conversation memory
- **Security verification** — DA coverage assessment + conditional opus re-scan

## Agent Prompts

Located in `agent-prompts/`. Each prompt has mandatory sections:
- `OUTPUT FORMAT — MANDATORY` (exact template)
- `FORBIDDEN` (no deviations)
- `LANGUAGE RULE` (PT-PT narrative)
- `SHUTDOWN RULE` (complete work before accepting shutdown)

## References

- `references/clickup-api-patterns.md` — Shared API patterns for all skills
