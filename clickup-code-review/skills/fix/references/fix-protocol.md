# Fix Protocol Reference (v5.3.1)

Technical reference for the fixing skill. The Maestro, specialist agents, DA, ClickUp Manager, and QA agents use this document for commit procedures, review protocols, evidence gates, and error handling.

**v5.0 Changes vs v4:**
- Evidence gate protocol for every status transition
- "code review" intermediate status
- Read-Ahead Queue: PREPARE paralelo + IMPLEMENT serial (v5.3.1)
- Commit SHA + Branch binding in ticket description
- `#### Decisões Fix` mandatory documentation
- All ClickUp operations via ClickUp Manager
- NO browser tests (exclusive to testing skill)

**API Patterns:** See `references/clickup-api-patterns.md` (at plugin root) for canonical token extraction, response handling, rate limiting, and error handling patterns.

**Key principle:** The fix skill reuses the SAME specialist agents from the audit skill. No dedicated fixer agents — the agent that found the issue implements the fix (with MODE: FIX instructions from the agent `.md` file).

---

## Comment Detection Before Fix (MANDATORY)

Before dispatching ANY ticket to a specialist, Maestro instructs ClickUp Manager to check for new comments.

### Protocol

```
0. Maestro instructs ClickUp Manager: fetch comments for ticket {id}
1. ClickUp Manager compares latest comment ID against last_comment_id in local .md frontmatter
2. ClickUp Manager reports new comments (if any) to Maestro
3. Maestro assesses impact:
   a. BREAKING CONTRADICTION → SKIP ticket, queue for re-planning
   b. NON-BREAKING ADJUSTMENT → Adapt local .md, pass enriched context to specialist
   c. COMPATIBLE/APPROVAL → Proceed normally
   d. QUESTION → Discuss with user via AskUserQuestion
4. ClickUp Manager updates last_comment_id in frontmatter regardless of outcome
```

### Re-plan invocation (for breaking contradictions)

1. Log: `"Ticket {id} skipped — breaking comment: '{summary}'"`
2. Ticket status stays at "ready for dev" (NOT "in progress")
3. After current wave completes, Maestro invokes `/clickup-code-review:planning` for skipped ticket(s) only
4. Re-planned tickets re-enter the fix queue in a subsequent wave or session

**This is non-blocking** — the rest of the wave continues while the skipped ticket is queued.

---

## Reading Ticket Context from Local Cache

Read the ticket's local `.md` file from `code-reviews/{review_dir}/{area_dir}/{task_id}.md`.

**Fix specialist reads UPDATED sub-sections first:**
- If `##### Correcção Sugerida (Actualizado após Planeamento)` exists inside `#### Planeamento`, it has PRECEDENCE over the original `#### Correcção Sugerida`
- Same for `##### Como Testar`, `##### Evidência`, `##### Impacto`
- If updated sub-sections don't exist, use original audit sections

**If local file doesn't exist** (v4.0.1 compat): ClickUp Manager falls back to `GET /task/{id}?include_markdown_description=true`, then creates the local file.

---

## Specialist -> DA Direct Communication Flow

The fixing pipeline follows **"review before commit"** with **direct specialist<->DA communication**. The Maestro does NOT intermediate between specialist and DA during the review loop.

### Per-Ticket Cycle

```
0. Maestro instructs ClickUp Manager: comment check (see above)
1. Maestro instructs ClickUp Manager: status -> "in progress" (evidence: .md local exists)
2. Specialist implements fix via Edit/Write (NUNCA faz git add — staging é exclusivo do Maestro)
3. Specialist writes per-file progress to {REVIEW_DIR}/progress/agent-{name}-progress.md
4. Specialist captures diff: `git diff <ficheiros>` (unstaged diff)
5. If diff <= 200 lines: send full diff to DA via SendMessage
   If diff > 200 lines: save to {REVIEW_DIR}/diffs/fix-{ticket_id}.diff, send stats + sample + path
6. Specialist reports to Maestro: DA verdict + LISTA EXACTA de ficheiros modificados
7. Maestro faz `git add <ficheiros específicos>` + `git commit` (1 commit por ticket)
8. Maestro instructs ClickUp Manager: status -> "code review" (evidence: diff sent to DA)
7. DA reviews:
   a. APPROVED -> specialist reports to Maestro (includes DA verdict + reasoning)
   b. REQUEST-CHANGES -> DA sends feedback to specialist -> specialist revises
      -> Maestro instructs ClickUp Manager: status -> "in progress"
      -> specialist corrects, re-stages, new diff to DA
      -> Maestro instructs ClickUp Manager: status -> "code review"
8. Loop max 2 rounds. After 2 rejections -> specialist escalates to Maestro
9. Maestro receives verdict -> commits (if APPROVED) or decides (if escalated)
10. Maestro instructs ClickUp Manager: evidence gate (Step 7 in SKILL.md)
11. After evidence gate passes: ClickUp Manager status -> "testing"
12. Each round of DA review documented in #### Decisões Fix
```

### Specialist -> DA SendMessage Template (MANDATORY)

The specialist MUST send ALL of the following context to the DA. Information asymmetry leads to rubber-stamp approvals.

```markdown
## CODE REVIEW — {Ticket Title}
**Ticket ID:** {clickup_task_id}
**Area:** {security/backend-perf/frontend/quality/complexity/qa}
**Severidade:** {from ticket}

### Original Finding
**Problema:** {full Problema text — use updated version from Planeamento if exists}
**Impacto:** {full Impacto text — use updated version from Planeamento if exists}

### Planned Fix (from Planeamento)
{full Correcção Sugerida steps — use updated version from Planeamento if exists}

### Files Modified
{list of files with brief description of each change}

### Diff
` ` `diff
{output of git diff <ficheiros> — unstaged diff, full or partial, see large diff protocol}
` ` `
```

### Large Diff Protocol

If diff exceeds 200 lines:
1. Save to `{REVIEW_DIR}/diffs/fix-{ticket_id}.diff`
2. Send to DA: statistics (files changed, insertions, deletions) + sample (first 50 lines) + path to full diff
3. DA reads full diff from file if needed

---

## Evidence Gate Protocol (v5.0 — NEW)

### Status Transitions with Evidence Requirements

| Transition | Evidence Required | Verified By |
|------------|-------------------|-------------|
| ready for dev -> in progress | MINIMUM: .md local exists. IDEAL: `#### Planeamento` present | ClickUp Manager |
| in progress -> code review | Diff captured + SendMessage sent to DA | ClickUp Manager |
| code review -> in progress | DA REQUEST-CHANGES verdict | ClickUp Manager |
| code review -> testing | DA APPROVED + Commit SHA verified + `#### Decisões Fix` documented | ClickUp Manager |

### Evidence Gate: code review -> testing (TRIPLE VERIFICATION)

All three conditions MUST pass:

1. **DA verdict == "APPROVED"** for CODE-REVIEW of this ticket
   - Maestro relays DA verdict to ClickUp Manager
   - ClickUp Manager confirms verdict is "APPROVED" (not "REQUEST-CHANGES")

2. **Commit SHA verified** via git log
   - ClickUp Manager runs: `git log -1 --grep={ticket_id} --format='%H'`
   - Output must match the commit SHA provided by Maestro
   - If no match -> REFUSE: "Commit nao encontrado ou SHA invalido"

3. **`#### Decisões Fix` documented** in local .md
   - ClickUp Manager checks that the section exists in the .md body
   - Section must contain: DA verdict, round number, reasoning
   - If missing -> REFUSE: "Eventos de code review nao documentados"

**If ANY verification fails:** ClickUp Manager REFUSES the status change and reports to Maestro.

### Sections Added After Evidence Gate Passes

ClickUp Manager consolidates `{REVIEW_DIR}/progress/agent-{name}-progress.md` into local `.md`:

```markdown
#### Fix Log
- **Specialist:** {agent-name}
- **Inicio:** {ISO timestamp}
- **Ficheiros modificados:**
  - `{filepath}` (+{ins} -{del})
  - ...
- **Fim:** {ISO timestamp}

#### Decisões Fix
- **DA (CODE-REVIEW) Round 1:** {APPROVED/REQUEST-CHANGES} — "{reasoning in PT-PT}"
- **Specialist:** {action taken if REQUEST-CHANGES}
- **DA (CODE-REVIEW) Round 2:** {verdict if applicable} — "{reasoning}"
- **Maestro:** {commit autorizado / override / skip}

#### Commit
- **SHA:** `{commit_sha}`
- **Branch:** `{branch_name}`
- **Data:** {ISO timestamp}
- **Ficheiros:** {N} modified (+{ins} -{del})
```

**Example with DA rejection (round 1 rejected, round 2 approved):**
```markdown
#### Decisões Fix
- **DA (CODE-REVIEW) Round 1:** REQUEST-CHANGES — "Falta null-check no ImportService linha 45. Se CSV vazio, $rows e null e foreach falha."
- **Specialist:** corrigido — adicionado `$rows = $rows ?? []` antes do foreach
- **DA (CODE-REVIEW) Round 2:** APPROVED — "Null-check correcto, fix completo."
- **Maestro:** commit autorizado
```

**Example with escalation to Maestro (2 rejections):**
```markdown
#### Decisões Fix
- **DA (CODE-REVIEW) Round 1:** REQUEST-CHANGES — "Service nao deve fazer redirect, so retornar dados."
- **Specialist:** corrigido — movido redirect para controller
- **DA (CODE-REVIEW) Round 2:** REQUEST-CHANGES — "Agora o controller tem logica de negocio no redirect. Extrair para metodo privado."
- **Specialist:** ESCALACAO — "DA pede extraccao que esta fora do scope do ticket."
- **Maestro:** OVERRIDE — "Fix resolve o bug original. Refactoring e scope futuro. Commit autorizado com nota."
```

---

## Read-Ahead Queue (v5.3.1)

**PREPARE paralelo (read-only, max 3) → persist .prepare.md → IMPLEMENT serial (write/report).**

### Phase A — PREPARE (paralelo, max 3 simultâneos)

1. Maestro spawna até 3 specialists em **MODE: PREPARE**
   - Specialists com dependências conhecidas NÃO são spawned nesta batch
2. Cada specialist (PREPARE):
   a. Lê ticket .md + TODOS os source files do Planeamento
   b. Regista mtimes dos ficheiros-alvo via `stat -f '%m' {file}`
   c. Planeia fix (que linhas alterar, adicionar, remover)
   d. Escreve plano em `{REVIEW_DIR}/prepare/ticket-{id}.prepare.md`
   e. Reporta "READY" ou "BLOCKED" ao Maestro via SendMessage
   f. Specialist termina (shutdown)
3. Se wave > 3 tickets: após batch terminar, spawnar próxima batch (FIFO)
4. BLOCKED: reporta ao Maestro, NÃO escreve .prepare.md

### Phase B — IMPLEMENT (serial, 1 de cada vez)

5. Antes de dispatch, Maestro faz **staleness check**:
   a. Lê .prepare.md → extrai lista de target files com mtimes
   b. Compara mtimes actuais vs registados (`stat -f '%m' {file}`)
   c. Se stale: flag "STALE — ficheiros alterados: {list}"
6. Maestro re-spawna specialist em **MODE: IMPLEMENT** com:
   - Ticket .md path + .prepare.md path + staleness flag (se aplicável)
7. Specialist: lê .prepare.md → se stale re-lê ficheiros → implementa → reporta ficheiros ao Maestro → diff ao DA
8. DA: CODE-REVIEW → APPROVED / REQUEST-CHANGES
9. APPROVED → Maestro commita → dispatch próximo

### Phase C — UNBLOCK (quando blocker committed)

10. Após commit de blocker → spawnar PREPARE para specialists BLOCKED
11. Segue Phase A normal (persist + terminate)

### Deadlock Detection

Se A BLOCKED on B e B BLOCKED on A → mover ticket com menor prioridade para próxima wave.
Log: "Deadlock detectado: {A} e {B} bloqueiam-se mutuamente."

### Fallback to Serial

Se PREPARE falha para qualquer specialist → esse ticket executa em modo serial (sem .prepare.md).
Restantes mantêm Read-Ahead.

### .prepare.md Format

```markdown
# PREPARE Report — {Ticket Title}
**Ticket ID:** {clickup_task_id}
**Status:** READY | BLOCKED
**Specialist:** {agent-type}
**Timestamp:** {ISO}

## Target Files (com mtimes para staleness check)
| File | mtime | Lines to Modify |
|------|-------|----------------|
| `{file1.php}` | {epoch} | L45-67: add null check |
| `{file2.blade.php}` | {epoch} | L12: fix form action |

## Planned Changes
### {file1.php}
- L45-67: Adicionar null check antes do foreach
- Razão: $rows pode ser null se CSV vazio

### {file2.blade.php}
- L12: Corrigir form action de POST para PUT
- Razão: Route usa PUT para update

## Dependencies
- None
  OU:
- BLOCKED by {ticket_id}: modifica `{shared_file}` (L30-50) que este ticket também precisa

## Estimated Scope
- Files: {N} | Lines: ~{estimate}
```

### Staleness Check Protocol

Maestro executa ANTES de cada IMPLEMENT dispatch:

```
1. Read {REVIEW_DIR}/prepare/ticket-{id}.prepare.md
2. Para cada ficheiro na tabela "Target Files":
   a. stat -f '%m' {filepath}
   b. Comparar epoch actual vs epoch registado
3. Se TODOS iguais: FRESH → dispatch IMPLEMENT normalmente
4. Se ALGUM diferente: STALE → incluir flag no spawn:
   "STALE — ficheiros alterados: {file1}, {file2}"
5. Specialist em MODE: IMPLEMENT com flag STALE:
   a. Re-lê APENAS ficheiros alterados
   b. Adapta plano conforme diferenças
   c. Prossegue com implementação
```

**FORBIDDEN (Read-Ahead Queue):**
- NUNCA spawnar >3 specialists em PREPARE simultaneamente
- NUNCA dar IMPLEMENT a 2+ specialists simultaneamente
- NUNCA dar IMPLEMENT a specialist BLOCKED (sem resolver blocker)
- NUNCA spawnar PREPARE para ticket com dependência conhecida não-resolvida
- PREPARE specialists NÃO fazem Write/Edit/git add — EXCEPTO escrever .prepare.md
- NUNCA fazer IMPLEMENT sem staleness check do .prepare.md
- NUNCA pre-dispatch IMPLEMENT enquanto DA revê ou staging ocupado

---

## Commit Format

```bash
git commit -m "fix: {concise description from ticket}

Ticket: {clickup_task_id}
Area: {area}"
```

**CRITICAL: NEVER use heredoc, AI attribution, or command substitution in commits. Multi-line via quotes only.**

**CRITICAL: Only the Maestro commits. Never a specialist or DA.**

---

## DA CODE-REVIEW Mode

The Devil's Advocate operates in **CODE-REVIEW** mode during the fixing skill.

### DA Verdicts

| Verdict | Meaning | Next step |
|---------|---------|-----------|
| **APPROVED** | Code is correct and safe | Specialist reports to Maestro -> Maestro commits |
| **REQUEST-CHANGES** | Issues found, needs revision | DA sends feedback to specialist |

### DA Revision Limits

- Maximum **2 revision rounds** per ticket (specialist<->DA direct loop)
- Round 1: DA sends REQUEST-CHANGES -> specialist revises -> re-implements -> new diff to DA
- Round 2: Same cycle
- After 2 rejections: specialist escalates to Maestro with COMPLETE feedback history
- Maestro decides: override (commit with note) or skip (ticket stays "in progress")

### DA Escalation to Maestro

DA only involves Maestro when:
- Uncertain whether to approve or reject
- Specialist and DA disagree after 2 rounds
- DA spots issue outside ticket scope

---

## QA Test Suite After Each Wave (NOT Browser Testing)

After each wave completes, QA Specialist runs test suite (PHPUnit/Pest):

```
1. Run: sail artisan test (or project equivalent)
2. Capture pass/fail/skip counts
3. Compare with baseline (pre-existing failures from audit phase)
4. If NEW tests fail (not in baseline): STOP, report to Maestro
5. If pre-existing failures unchanged: proceed to next wave
6. Record results in {REVIEW_DIR}/qa/test-suite-{date}.md
```

**Browser testing (Chrome DevTools MCP) does NOT happen here.** It is exclusive to the `/clickup-code-review:testing` skill.

---

## Status Flow (Fix Skill v5.0)

```
ready for dev
    |
    v (evidence: .md local exists + Planeamento)
in progress
    |
    v (evidence: staged diff + sent to DA)
code review          ← NEW status in v5.0
    |
    ├── DA APPROVED + commit → evidence gate
    |                            |
    |                            v (evidence: SHA + Decisões Fix + DA verdict)
    |                         testing
    |
    └── DA REQUEST-CHANGES → in progress (specialist corrects)
                                |
                                v (re-stage, new diff)
                             code review (round 2)
```

**NEVER batch status updates. Update per ticket, per action, via ClickUp Manager.**

---

## Frontmatter Updates (per ticket, after each action)

ClickUp Manager updates local `.md` frontmatter after each status change:

| Field | When Updated |
|-------|-------------|
| `status` | Every status transition |
| `last_synced` | Every PUT to ClickUp |
| `last_comment_id` | After comment check (Step 0) |
| `commit_sha` | After evidence gate (Step 7) |
| `branch` | After evidence gate (Step 7) |
| `fix_attempts` | Incremented per fix attempt |

---

## Wave Conflict Detection

```
for each pair (A, B) in the wave:
  if A.files_to_modify INTERSECT B.files_to_modify != empty:
    move ticket with LOWER priority to next wave
    log: "Conflict: A and B both modify {overlap}. Moved {lower} to next wave."
```

Priority: ClickUp priority (1=Urgent > 4=Low). Same priority: fewer file modifications stays.

---

## Branch Strategy

Shared branch only. No per-ticket branches.

```bash
git checkout -b fix/clickup-review-$(date +%Y-%m-%d)
```

**NEVER push or merge automatically.**

---

## Error Handling

| Scenario | Recovery |
|----------|----------|
| DA rejects code twice | Specialist escalates to Maestro. Override or skip. |
| New tests fail after wave | STOP wave. Investigate if caused by fix. Specialist corrects or skip. |
| File conflict within wave | Move conflicting ticket to next wave |
| ClickUp API rate limit | ClickUp Manager handles (proactive 80/min, 429: wait 60s) |
| Specialist cannot implement | Report failure, skip, ClickUp Manager adds comment |
| Evidence gate fails | ClickUp Manager refuses status change, alerts Maestro |
| Planning data missing | Skip ticket, ClickUp Manager adds comment |
| Breaking comment detected | SKIP ticket, queue for re-planning |
| Agent dies mid-task | Check {REVIEW_DIR}/progress/ progress, re-spawn with recovered context |
| Git merge conflict | Maestro resolves, or skip ticket |

---

## Credential Security Rule

**MANDATORY for ALL content in diffs, messages, and tickets:**
- NEVER include real credentials (passwords, API keys, tokens, secrets)
- ALWAYS use placeholders: `{API_KEY}`, `{DB_PASSWORD}`, `{TOKEN}`
- ClickUp Manager enforces credential scan on all content before PUT
