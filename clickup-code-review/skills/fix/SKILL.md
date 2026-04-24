---
name: clickup-code-review:fix
description: Implement fixes for validated ClickUp code review tickets. Handles branching, wave execution, DA code review with evidence gates, and status updates through "deploy to staging". Uses ClickUp Manager for ALL API operations. Checks for new ClickUp comments before each fix. Use when the user asks to "fix the review tickets", "implement the planned fixes", "execute the code review fixes", or "start fixing wave 1". Use after planning has prepared tickets.
user_invocable: true
---

# ClickUp Code Review — Fix Skill (v5.4.0)

Execute planned fixes for validated tickets. Read-Ahead Queue — PREPARE paralelo (max 3) + IMPLEMENT serial. DA CODE-REVIEW + evidence gate + commit per ticket.

**BEFORE Phase 1:** Read `references/fix-protocol.md` for per-ticket cycle, evidence gate details, commit format.
**API Patterns:** See `references/clickup-api-patterns.md` for all ClickUp API patterns.

---

## FORBIDDEN (Maestro) — LER PRIMEIRO

1. NUNCA implementar fixes directamente. Specialists implementam, DA revê, Maestro commita.
2. NUNCA usar `/tmp/`. Tudo em `code-reviews/`.
3. NUNCA usar `grep -P`. Usar `grep -E`.
4. NUNCA enviar shutdown_request sem ordem explícita do user.
5. NUNCA re-spawnar agentes sem verificar se estão vivos (SendMessage "Status?").
6. NUNCA fazer side-work durante fix activo. Contexto é finito.
7. NUNCA ler agent .md files. Cada agente lê-se a si próprio.
8. NUNCA fazer commit sem DA APPROVED verdict.
9. NUNCA fazer push. Decisão do user.
10. NUNCA assumir scope. Se o user não especificou, PERGUNTAR via AskUserQuestion.
11. NUNCA fechar tickets sem validação de specialist + DA.
12. NUNCA fazer trabalho de specialist. Se envolve source code, DELEGAR.
13. NUNCA enviar shutdown_request sem que DA e CU Manager confirmem SEM pendentes.
14. NUNCA gerar bash multi-linha ou com `&&`/`||`/`;`. Cada Bash call = 1 statement.
    Para listar ficheiros: **Glob TOOL**. Para ler: **Read TOOL**.
15. NUNCA incluir atribuição de autoria AI em commits. Formato: single-line com Ticket ID e Area.

---

## Shutdown Rules (v5.4.0)

### Quando fechar agentes
Maestro PODE fechar specialists no FINAL de cada wave. DA e CU Manager persistem toda a sessão.

### Protocolo de shutdown
ANTES de shutdown_request:
1. Perguntar ao DA: "Tens processos pendentes com {specialist}?"
2. Perguntar ao CU Manager: "Tens syncs pendentes com {specialist}?"
3. SÓ se AMBOS confirmarem "sem pendentes" → enviar shutdown_request

### FORBIDDEN
- NUNCA fechar DA ou CU Manager (excepto fim de sessão por ordem do user)
- NUNCA fechar specialists sem confirmação do DA E do CU Manager
- NUNCA fechar specialists a MEIO de uma wave

---

## Spawn Order (MANDATORY)

**Step 0 — TeamCreate (OBRIGATÓRIO — sem isto SendMessage não funciona):**
```
TeamCreate(team_name="cc-fix-{shortname}-{date}", description="Code Review fix phase")
```
TODOS os agentes spawned com `team_name` e `name` para comunicação via SendMessage.

```
1. CU Manager: Task(team_name="cc-fix-...", name="cu-manager") → config check + status mapping + local cache
2. CU Manager → Maestro: READY + paths
3. DA: Task(team_name="cc-fix-...", name="da") → CODE-REVIEW mode → wait READY
4. Specialists: Task(team_name="cc-fix-...", name="{specialist}") → per wave, PREPARE paralelo (max 3) + IMPLEMENT serial
```

---

## Read-Ahead Queue (v5.4.0)

**PREPARE paralelo (read-only, max 3) → persist .prepare.md → IMPLEMENT serial (write/report).**

### Phase A — PREPARE (paralelo, max 3 simultâneos)

1. Maestro spawna até 3 specialists em **MODE: PREPARE**
   - Specialists com dependências conhecidas NÃO são spawned nesta batch
2. Cada specialist (PREPARE):
   a. Lê ticket .md + TODOS os source files do Planeamento
   b. Regista mtimes dos ficheiros-alvo
   c. Planeia fix (que linhas alterar, adicionar, remover)
   d. Escreve plano em `{REVIEW_DIR}/prepare/ticket-{id}.prepare.md`
   e. Reporta "READY" ou "BLOCKED" ao Maestro via SendMessage
   f. Specialist termina (shutdown)
3. Se wave > 3 tickets: após batch terminar, spawnar próxima batch (FIFO)
4. BLOCKED: reporta ao Maestro, NÃO escreve .prepare.md

### Phase B — IMPLEMENT (serial, 1 de cada vez)

5. Antes de dispatch, Maestro faz **staleness check**:
   a. Lê .prepare.md → extrai lista de target files com mtimes
   b. Compara mtimes actuais vs registados
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

**FORBIDDEN (Maestro — Read-Ahead Queue):**
- NUNCA spawnar >3 specialists em PREPARE simultaneamente
- NUNCA dar IMPLEMENT a 2+ specialists simultaneamente
- NUNCA dar IMPLEMENT a specialist BLOCKED (sem resolver blocker)
- NUNCA spawnar PREPARE para ticket com dependência conhecida não-resolvida
- PREPARE specialists NÃO fazem Write/Edit/git add — EXCEPTO escrever .prepare.md
- NUNCA fazer IMPLEMENT sem staleness check do .prepare.md
- NUNCA pre-dispatch IMPLEMENT enquanto DA revê ou staging ocupado

**Evidence gate failure (CU Manager recusa status change):**
- Sem DA APPROVED: aguardar DA → re-enviar diff se necessário
- Sem commit SHA (e DA APPROVED já confirmado): Maestro verifica git log → commit se em falta
- Sem `#### Decisões Fix`: instruir specialist a adicionar secção → re-submit

---

## Prerequisites

- Tickets at "ready for dev" status (prepared by `/clickup-code-review:planning`)
- Each ticket has `#### Planeamento` section in local `.md` file
- ClickUp API token and list ID configured

## Pipeline Position

```
/clickup-code-review:audit     ->  Audit (creates tickets at "open")
/clickup-code-review:planning  ->  Triage (open -> planning -> ready for dev)
/clickup-code-review:fix       ->  THIS SKILL (ready for dev -> ... -> testing)
/clickup-code-review:testing   ->  Validate (testing -> deploy to staging)
```

---

## Phase 0: Configuration Check

0. **Hook guard activation:** `mkdir -p code-reviews` seguido de `touch code-reviews/.clickup-review-active` (2 Bash calls separadas) (enables plugin hooks for this session)
1. Gitignore: verify `code-reviews/` in `.gitignore`
2. CU Manager: config check (token, list ID, shortname, status mapping)
3. CU Manager: RECONCILE CACHE (1x per session)
4. CU Manager: check for tickets at "in progress"/"code review" → present to user if found

---

## Phase 0B: Fix Scope Selection

1. CU Manager: fetch tickets at "ready for dev"
2. AskUserQuestion (multiSelect): areas to fix (Todas, Security, Backend/Performance, Frontend, Quality, Code Simplifier, QA)
3. Read local `.md` files: parse `#### Planeamento` for routing metadata (Agente, Wave, Ficheiros, Dependências)
4. Wave conflict check: if A and B share files → move lower-priority to next wave
5. Present wave plan to user + AskUserQuestion: "Avancar com os fixes?"

---

## Phase 0C: Branch Setup

```bash
git status
git checkout -b fix/clickup-review-$(date +%Y-%m-%d)
```

If branch exists (resumed session): ask user to continue or create new.

---

## Phase 1-N: Wave Execution (Read-Ahead Queue)

**Full per-ticket cycle in `references/fix-protocol.md`.** Summary:

**PLUGIN_ROOT:** Obter via `Bash "echo $CLAUDE_PLUGIN_ROOT"` uma vez no início. Incluir em CADA spawn de specialist.

For EACH ticket in current wave:
1. CU Manager: comment check → assess impact → proceed/skip/adapt
2. Maestro provides FULL context to specialist: ticket ID + Problema + Impacto + Planeamento (updated sub-sections have PRECEDENCE) + Plugin root: {PLUGIN_ROOT}
3. CU Manager: status → "in progress"
4. Specialist: implements fix + reports modified files to Maestro + sends diff to DA (CODE-REVIEW template in fix-protocol.md)
5. CU Manager: status → "code review"
6. DA APPROVED → specialist reports ficheiros modificados ao Maestro
   → Maestro faz `git add <ficheiros>` + `git commit` (staging exclusivo do Maestro)
   DA REQUEST-CHANGES → specialist corrects → new diff to DA (max 2 rounds)
7. CU Manager: evidence gate (SHA + `#### Decisões Fix` + DA APPROVED) → status → "testing"

After ALL tickets in wave:
1. `git status` — verify clean staging
2. QA Specialist: `sail artisan test` + compare with baseline. If NEW failures → STOP.

---

## Phase Final: Summary

```markdown
## Fix Summary — {date}
### Branch: fix/clickup-review-{date}
| Ticket | Title | Area | Status | Commit | DA Rounds |
### Statistics
- Total processed: {N} | At testing: {X} | Skipped: {Y}
- Test suite: {pass}/{fail} (baseline: {pass_b}/{fail_b})
### Next steps
"Para testes: /clickup-code-review:testing"
"NUNCA faço push — essa decisão é tua."
```

---

## Checklist (Maestro verifica ANTES de reportar ao user)

- [ ] Gitignore checked for `code-reviews/`
- [ ] CU Manager spawned, config validated, cache reconciled
- [ ] Branch created
- [ ] All tickets had comment check before dispatch
- [ ] Maestro NEVER implemented fixes directly (all by specialists)
- [ ] Each specialist received FULL ticket context (Problema + Impacto + Planeamento)
- [ ] DA spawned ONCE in CODE-REVIEW mode, reused for all tickets
- [ ] "code review" intermediate status used correctly
- [ ] Evidence gate passed for ALL committed tickets (SHA + Decisões Fix + DA APPROVED)
- [ ] All local `.md` files have Fix Log + Decisões Fix + Commit sections
- [ ] All local `.md` files synced to ClickUp (via CU Manager)
- [ ] Test suite ran after each wave (QA Specialist)
- [ ] All tickets at correct status ("testing" or skipped)
- [ ] Summary presented to user
- [ ] User informed: NEVER auto-push
- [ ] Hook guard deactivated: `rm -f code-reviews/.clickup-review-active`
