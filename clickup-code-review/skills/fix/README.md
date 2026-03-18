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
4. **Phase 1-N** — Wave execution (Read-Ahead Queue: PREPARE paralelo + IMPLEMENT serial)
5. **Phase Final** — Summary with commit log

### Read-Ahead Queue (v5.2.0)

**Phase A — PREPARE (paralelo, max 3 simultaneous):**
```
- Specialists read ticket + source files (read-only)
- Persist plan to {REVIEW_DIR}/prepare/ticket-{id}.prepare.md
- Report READY/BLOCKED → terminate
```

**Phase B — IMPLEMENT (serial, 1 at a time):**
```
0. Maestro fetches comments → assesses impact
1. Staleness check: compare file mtimes vs .prepare.md
2. Re-spawn specialist in MODE: IMPLEMENT with .prepare.md
3. Specialist implements fix → stages → sends diff to DA
4. DA CODE-REVIEW → APPROVED / REQUEST-CHANGES
5. APPROVED → Maestro commits → next ticket
6. Evidence gate → status "testing"
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
