# Fix Skill — `/clickup-code-review:fix`

Execute planned fixes for validated tickets. Manage branches, coordinate specialist agents with DA code review, run QA validation, and update ClickUp status through the full lifecycle.

## Pipeline Position

```
/clickup-code-review           →  Audit (creates tickets at "open")
/clickup-code-review:planning  →  Triage (open → planning → ready for dev)
/clickup-code-review:fix       ←  THIS SKILL (ready for dev → deploy to staging)
```

**Prerequisite:** The planning skill (`/clickup-code-review:planning`) must have run first. This skill operates on tickets at "ready for dev" status with enriched descriptions and `#### Planeamento` metadata.

## How It Works

1. **Phase 0** — Configuration check + status mapping + resume detection
2. **Phase 0B** — Fetch "ready for dev" tickets, area selection, wave plan
3. **Phase 0C** — Branch setup (`fix/clickup-review-YYYY-MM-DD`)
4. **Phase 1-N** — Wave execution (sequential waves, parallel tickets within waves)
5. **Phase Final** — Summary with commit log

### Per-Ticket Cycle (within a wave)

```
0. Maestro fetches comments → compares against last_comment_id in local .md
   - Breaking contradiction → SKIP, queue for re-planning
   - Non-breaking adjustment → Adapt local .md, continue
   - Compatible → Proceed normally
1. Update status → "in progress"
2. Read ticket context from local .md file (not from ClickUp API)
3. Spawn specialist agent (same agent type that found the issue)
4. Specialist implements fix → stages with git add → captures diff
5. Specialist sends diff + full context to DA via SendMessage
6. DA reviews (CODE-REVIEW mode) → APPROVED or REQUEST-CHANGES
7. If APPROVED → Maestro commits → updates local .md frontmatter
8. QA validation (unit/e2e/both/none based on Planeamento)
9. If QA PASS → update status → "deploy to staging" → update frontmatter
10. If QA FAIL → git revert, retry (max 2 attempts) → update frontmatter
```

## Key Principles

### Maestro NEVER Implements Fixes

The Maestro is an ORCHESTRATOR, not an IMPLEMENTER. All source code changes are made by specialist agents with DA review. No exceptions, not even for "simple" 1-line fixes.

### Specialist ↔ DA Direct Communication

The specialist sends diffs directly to the DA via SendMessage. The Maestro does NOT intermediate. This preserves full context and reduces message overhead.

### Comment Detection Before Fix

Before dispatching ANY ticket, Maestro checks for new comments since planning. Breaking contradictions are skipped and queued for re-planning (non-blocking). Non-breaking adjustments are incorporated into the local `.md` file.

### Transversal Ticket Context

ALL participants (Maestro, specialist, DA) receive the FULL ticket context from the local `.md` file: Ticket ID, Problema, Impacto, Correcção Sugerida, Feedback Humano, Planeamento metadata.

### Large Diff Protocol

If staged diff exceeds 200 lines: save to `{REVIEW_DIR}/diffs/fix-{ticket_id}.diff`, send stats + sample (first 50 lines) + file path to DA.

## Status Flow

```
ready for dev → in progress → testing → deploy to staging
                    ↑              |
                    └── (QA FAIL: revert, retry)
```

## References

- `references/fix-protocol.md` — Comment detection, re-plan invocation, commit format, DA review, QA validation, rollback, local cache read
- `references/clickup-api-patterns.md` — Shared API patterns, comment endpoint, local cache conventions (plugin root)
