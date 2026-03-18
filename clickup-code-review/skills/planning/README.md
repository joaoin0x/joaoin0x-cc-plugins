# Planning Skill — `/clickup-code-review:planning` (v5.1.1)

Triage and validate existing code review tickets via decentralised planning. Each specialist plans their own area, validated by DA + Investigation (triangle validation). Investigation does meta-organisation (waves, dependencies, ticket consolidation). ClickUp Manager handles ALL API operations.

## Pipeline Position

```
/clickup-code-review:audit     →  Audit (creates tickets at "open")
/clickup-code-review:planning  ←  THIS SKILL (open → planning → ready for dev)
/clickup-code-review:fix       →  Execute (ready for dev → deploy to staging)
/clickup-code-review:testing   →  Validate (testing → deploy to staging)
```

**Prerequisite:** The audit skill must have run first. This skill operates on tickets at "open" or "planning" status.

## How It Works

1. **Phase 0** — Configuration check + status case-mapping + local cache detection + gitignore check
2. **Phase 0B** — Fetch tickets, area selection (auto-skipped if same session as audit), present scope
3. **Phase 1** — Decentralised Planning (Triangle Validation)
   - Comment detection per ticket
   - Read local `.md` files
   - Spawn DA + Investigation (BEFORE specialists)
   - Spawn area specialists in parallel (each plans their own tickets)
   - Triangle: Specialist ↔ DA ↔ Investigation (direct SendMessage)
4. **Phase 2** — Meta-Organisation (Investigation + DA ping-pong) — waves, dependencies, merges
5. **Phase 3** — ClickUp Updates via CU Manager — write Planeamento section, forward-references, PUT to ClickUp
6. **Phase 4** — Summary with wave plan

## Key Concepts

### Local File Cache

Planning reads ticket descriptions from local `.md` files (created during audit). All composition happens locally, then PUTs to ClickUp. **No GET→modify→PUT cycle.** Audit sections are IMMUTABLE — refined versions go as `#####` sub-sections within `#### Planeamento`.

### Triangle Validation

Each specialist proposes 2 approaches (A/B). DA and Investigation validate concurrently. Both send VALID/INVALID to specialist AND Maestro (NEEDS-CHANGE goes to specialist only). Max 2 NEEDS-CHANGE rounds before escalation.

### Planeamento Template

See `skills/shared/planning-protocol.md` for the canonical template. Key fields: Agente, Abordagem, QA, Ficheiros, Dependências, Wave, Estimativa.

### Role Separation

- **Maestro:** Orchestrates, NEVER investigates. Does NOT touch ClickUp API.
- **ClickUp Manager:** ALL ClickUp API operations, file writes, frontmatter updates.
- **Specialists:** Plan their own area's tickets, communicate directly with DA + Investigation.
- **DA:** Validates plans (PLANNING-REVIEW mode), concurrent with specialists.
- **Investigation:** Cross-area analysis, meta-organisation (waves, deps, merges).

## References

- `references/investigation-protocol.md` — Data formats, local cache read/write, status mapping
- `skills/shared/planning-protocol.md` — Specialist planning skeleton + Planeamento template
- `references/clickup-api-patterns.md` — Shared API patterns (plugin root)
