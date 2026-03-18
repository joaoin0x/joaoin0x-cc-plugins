---
name: clickup-code-review:testing
description: Functional browser testing via Chrome DevTools MCP with ClickUp ticket lifecycle management. Validates post-fix tickets, discovers new bugs, handles QA fail severity routing (MINOR/MODERATE/CRITICAL). Uses DA QA-REVIEW for ticket validation and FINDING-FILTER for new bugs. Use when the user asks to "test the application", "run browser tests", "validate the fixes", "run functional tests", or "check tickets in testing status".
user_invocable: true
---

# ClickUp Code Review — Testing Skill (v5.1.1)

Functional browser testing via Chrome DevTools MCP. Validates post-fix tickets, discovers new bugs, manages QA lifecycle with DA QA-REVIEW.

**CRITICAL DEPENDENCY:** Chrome DevTools MCP MANDATORY. If not available → report to user → do NOT proceed.
**BEFORE testing:** Read `references/testing-protocol.md` for Chrome DevTools MCP methodology, login handling, evidence format.
**API Patterns:** See `references/clickup-api-patterns.md` for all ClickUp API patterns.

---

## FORBIDDEN (Maestro) — LER PRIMEIRO

1. NUNCA testar directamente via browser. Delegar ao QA Specialist.
2. NUNCA fazer downgrade de profundidade. Se user escolheu "Funcional" → Level 2 OBRIGATÓRIO.
   "Navigate + check title" é smoke, NÃO funcional.
3. NUNCA testar >5 páginas sem QA Specialist spawned. Sem QA activo após 5 min → PARAR e spawnar.
4. NUNCA usar curl/wget como alternativa ao Chrome DevTools MCP.
5. NUNCA usar `/tmp/`. Tudo em `.claude/code-reviews/`.
6. NUNCA assumir scope. Se o user não especificou, PERGUNTAR via AskUserQuestion.
7. NUNCA fechar tickets sem validação de DA.
8. NUNCA enviar shutdown_request sem que DA e CU Manager confirmem SEM pendentes.
9. NUNCA gerar bash multi-linha ou com `&&`/`||`/`;`. Cada Bash call = 1 statement.
   Para listar ficheiros: **Glob TOOL**. Para ler: **Read TOOL**.

---

## Shutdown Rules (v5.1.1)

### Quando fechar agentes
Maestro PODE fechar QA Specialist no FINAL de cada phase. DA e CU Manager persistem toda a sessão.

### Protocolo de shutdown
ANTES de shutdown_request:
1. Perguntar ao DA: "Tens processos pendentes com {specialist}?"
2. Perguntar ao CU Manager: "Tens syncs pendentes com {specialist}?"
3. SÓ se AMBOS confirmarem "sem pendentes" → enviar shutdown_request

### FORBIDDEN
- NUNCA fechar DA ou CU Manager (excepto fim de sessão por ordem do user)
- NUNCA fechar specialists a MEIO de uma phase

---

## Prerequisites

- Chrome DevTools MCP available and functional
- For ticket validation: tickets at "testing" status (prepared by `/clickup-code-review:fix`)
- ClickUp API token and list ID configured

## Pipeline Position

```
/clickup-code-review:audit     ->  Audit (creates tickets at "open")
/clickup-code-review:planning  ->  Triage (open -> planning -> ready for dev)
/clickup-code-review:fix       ->  Execute (ready for dev -> ... -> testing)
/clickup-code-review:testing   ->  THIS SKILL (testing -> deploy to staging)
```

---

## Phase 0: Configuration Check

1. Gitignore: verify `.claude/code-reviews/` in `.gitignore`
2. CU Manager: config check (token, list ID, shortname, status mapping)
3. CU Manager: RECONCILE CACHE (1x per session)
4. **TeamCreate (OBRIGATÓRIO — sem isto SendMessage não funciona):**
   ```
   TeamCreate(team_name="cc-testing-{shortname}-{date}", description="Code Review testing phase")
   ```
5. Spawn order (TODOS com team_name):
   - CU Manager: `Task(team_name="cc-testing-...", name="cu-manager")`
   - DA: `Task(team_name="cc-testing-...", name="da")` → QA-REVIEW mode
   - QA Specialist: `Task(team_name="cc-testing-...", name="qa")` → TESTING mode
   **PLUGIN_ROOT:** Obter via `Bash "echo $CLAUDE_PLUGIN_ROOT"` antes de spawnar. Incluir no spawn de QA Specialist: `"Plugin root: {PLUGIN_ROOT} — lê o teu agent .md em {PLUGIN_ROOT}/agents/qa-specialist.md."`
5. QA Specialist: verify Chrome DevTools MCP available. If NOT → report to Maestro → STOP.
   **Maestro STOP playbook:** AskUserQuestion "Chrome DevTools MCP indisponível — abortar sessão ou aguardar?".
   Se abortar → shutdown DA + CU Manager (protocolo normal) → terminar skill.
   Se aguardar → manter agentes activos → re-tentar após instrução do user.

---

## Phase 0B: Test Mode Selection

```
AskUserQuestion:
header="Modo de Teste" question="Qual modo de teste queres executar?"
- "Smoke": todas as páginas — carrega + console + network (~17min)
- "Funcional": páginas com CRUD/forms — smoke + interacções completas (~45-90min)
- "Tickets": apenas páginas dos tickets em "testing" — validação pós-fix
- "Completo" (default): smoke tudo + funcional crítico (~45min)
```

### Level 2 — Funcional — DEFINIÇÃO

Testar CADA elemento interactivo em CADA página:
- Listings: search, paginação, filtros, sorting, bulk actions
- Forms: preencher TODOS os campos obrigatórios, submit, verificar sucesso/validação
- CRUD: Create → Show → Edit → Delete (ciclo COMPLETO)
- Modals/dialogs: abrir, interagir, fechar, confirmar, cancelar
- State transitions: mudanças de status, approval flows

**ATENÇÃO:** "Navigate + check title" é smoke, NÃO funcional.
Ver `references/functional-checklists.md` para checklists por tipo de página.

---

## Phase 1: Login & Setup

1. QA Specialist: credential detection — (1) `.claude/credentials.local.md` (2) `.env` (3) AskUserQuestion
2. QA Specialist: login via Chrome DevTools MCP + verify success
3. QA Specialist: test suite baseline (PHPUnit/Pest) → `{REVIEW_DIR}/qa/test-suite-{date}.md`

### Agent Spawn Checkpoint (OBRIGATÓRIO)

Se 5 minutos passaram desde o início da skill e DA OU QA Specialist NÃO estão activos:
→ PARAR toda actividade → spawnar agentes em falta IMEDIATAMENTE (DA antes de QA)

---

## Phase 2: Page Mapping

- **tickets mode:** CU Manager fetches tickets at "testing" → extract URLs
- **other modes:** QA Specialist reads routes + organizes by module. Priority: "testing" tickets first.

---

## Phase 3: Test Execution

QA Specialist executes per `references/testing-protocol.md`:
- Level 1 (ALL pages): navigate + wait + title check + console + network
- Level 2 (CRUD/form pages): full functional (see functional-checklists.md)

### Progress Report (10 min checkpoint)
Maestro reporta ao user a cada ~10 min: `"Progresso: {N} páginas testadas ao nível {funcional/smoke}. Profundidade correcta?"`

### Progress tracking
QA Specialist appends to `{REVIEW_DIR}/qa/qa-progress.md` after EACH page.

---

## Phase 4: Ticket Validation (tickets at "testing")

For EACH ticket at "testing":
1. QA Specialist: read local `.md` → navigate URL → reproduce original bug scenario → verify FIXED
2. QA Specialist: verify no regressions (console, network, CRUD)
3. QA Specialist → DA (QA-REVIEW): send evidence (ticket ID, URLs, actions, bug status, console, network)
4. DA APPROVED → CU Manager: status → "deploy to staging" + add `#### QA Results` + `#### Decisões Testing`
5. DA REJECTED → severity routing:
   - MINOR → status: "ready for dev" (quick-fix)
   - MODERATE/CRITICAL → status: "planning" + Maestro alert

For security/performance tickets: DA does COMBINED QA-REVIEW + CODE-REVIEW (browser evidence + source code).

---

## Phase 5: New Bug Discovery

Bugs found during smoke/funcional/completo:
1. QA Specialist → DA (FINDING-FILTER): Standard Finding Format
2. DA APPROVED → CU Manager: create new ticket (status "open")
3. DA REJECTED → log, no ticket

---

## Phase Final: Summary

```markdown
## Testing Summary — {date}
### Mode: {smoke/funcional/tickets/completo}
| Pages Tested | Passed | Failed | Pass Rate |
### Ticket Validation
| Ticket | DA Verdict | Severity | Routing |
### New Bugs Found
| Bug | Severity | DA Verdict | Ticket ID |
### Next steps
"Tickets QA-APPROVED estão em 'deploy to staging'."
"Para corrigir rejeitados: /clickup-code-review:fix"
```

---

## Checklist (Maestro verifica ANTES de reportar ao user)

- [ ] Gitignore: `.claude/code-reviews/` presente
- [ ] CU Manager spawned, config validated, cache reconciled
- [ ] Chrome DevTools MCP verified available by QA Specialist
- [ ] Test mode selected by user
- [ ] QA Specialist logged in successfully
- [ ] Test suite baseline captured
- [ ] Agent Spawn Checkpoint: QA Specialist activo antes dos 5 min
- [ ] For ticket mode: all "testing" tickets fetched via CU Manager
- [ ] Each ticket validated with full evidence
- [ ] DA QA-REVIEW verdicts received for all tickets
- [ ] QA-APPROVED tickets moved to "deploy to staging"
- [ ] QA-REJECTED tickets routed correctly (MINOR→ready for dev, MOD/CRIT→planning)
- [ ] Security/perf tickets: combined QA+Code Review done by DA
- [ ] New bugs created as tickets (if approved by DA)
- [ ] All local `.md` files updated with QA Results + Decisões Testing
- [ ] All local `.md` files synced to ClickUp (via CU Manager)
- [ ] Screenshots deleted by QA Specialist before shutdown
- [ ] Summary presented to user
