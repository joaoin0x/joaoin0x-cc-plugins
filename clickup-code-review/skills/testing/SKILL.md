---
name: clickup-code-review:testing
description: Functional browser testing via Chrome DevTools MCP with ClickUp ticket lifecycle management. Validates post-fix tickets, discovers new bugs, handles QA fail severity routing (MINOR/MODERATE/CRITICAL). Uses DA QA-REVIEW for ticket validation and FINDING-FILTER for new bugs. This skill should be used when the user says "test the application", "run browser tests", "validate the fixes", "run functional tests", "check tickets in testing status", "check design system consistency", or "run visual/UI quality checks".
user_invocable: true
---

# ClickUp Code Review — Testing Skill (v5.2.4)

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
8. NUNCA enviar shutdown_request sem ordem EXPLÍCITA do user. Ver Shutdown Rules.
9. NUNCA gerar bash multi-linha ou com `&&`/`||`/`;`. Cada Bash call = 1 statement.
   Para listar ficheiros: **Glob TOOL**. Para ler: **Read TOOL**.
10. NUNCA criar tickets directamente. TODA criação de tickets vai via CU Manager.
    Maestro instrui CU Manager via SendMessage, NUNCA usa a API directamente.
11. NUNCA saltar o DA. QUALQUER finding (bugs, órfãs, design, visual, i18n)
    deve ser encaminhado ao DA para FINDING-FILTER antes de criar ticket.
    "Factual" não significa "relevante" — o DA valida relevância.
12. NUNCA acumular findings para batch. Cada DA verdict → SendMessage ao CU Manager
    IMEDIATAMENTE (streaming). Não esperar pelo fim da sessão.

---

## Shutdown Rules (v5.2.4)

### Regra Absoluta
NUNCA enviar shutdown_request a QUALQUER agente sem ordem EXPLÍCITA do user.
Agentes ficam em standby após completar o seu trabalho.
O user decide quando fechar — NÃO o Maestro.

### Protocolo (quando o user PEDIR para fechar)
ANTES de shutdown_request:
1. Perguntar ao DA: "Tens processos pendentes com {specialist}?"
2. Perguntar ao CU Manager: "Tens syncs pendentes com {specialist}?"
3. SÓ se AMBOS confirmarem "sem pendentes" → enviar shutdown_request

### FORBIDDEN
- NUNCA fechar agentes por iniciativa própria (NUNCA, sem excepções)
- NUNCA fechar DA ou CU Manager sem ordem explícita do user
- NUNCA fechar specialists a MEIO de uma phase
- Apresentar summary e ESPERAR — o user pode querer reutilizar agentes

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
   **PLUGIN_ROOT:** Obter via `Bash "echo $CLAUDE_PLUGIN_ROOT"` antes de spawnar.

   - CU Manager: `Task(team_name="cc-testing-...", name="cu-manager")`
     **Spawn prompt:**
     ```
     MODE: TESTING
     Plugin root: {PLUGIN_ROOT}
     Lê o teu agent .md em {PLUGIN_ROOT}/agents/clickup-manager.md
     Lê references/clickup-api-patterns.md
     Operações esperadas: config check, cache reconcile, fetch tickets "testing",
     status changes (testing→deploy to staging, testing→ready for dev, testing→planning),
     criar tickets novos (findings QA aprovados pelo DA).
     Persistes toda a sessão. Instruções de status change vêm do Maestro.
     ```

   - DA: `Task(team_name="cc-testing-...", name="da")`
     **Spawn prompt:**
     ```
     MODE: QA-REVIEW
     Plugin root: {PLUGIN_ROOT}
     Lê o teu agent .md em {PLUGIN_ROOT}/agents/devils-advocate.md
     Lê {PLUGIN_ROOT}/skills/testing/references/testing-protocol.md (secção QA→DA SendMessage Templates)
     Vais receber evidência do QA Specialist via SendMessage.
     Para cada ticket: emitir QA-APPROVED ou QA-REJECTED + severity.
     Para findings novos: emitir APPROVED ou REJECTED (FINDING-FILTER).
     TODOS os verdicts vão para o Maestro (SendMessage). NUNCA para CU Manager directamente.
     ```

   - QA Specialist: `Task(team_name="cc-testing-...", name="qa")`
     **Spawn prompt:**
     ```
     MODE: TESTING
     Plugin root: {PLUGIN_ROOT}
     Lê o teu agent .md em {PLUGIN_ROOT}/agents/qa-specialist.md
     Lê references/testing-protocol.md (Snapshot-First + Human Usage + Design System SOT + Visual/UI)
     Lê references/functional-checklists.md (checklists funcionais por tipo de página)

     REGRAS CRITICAS:
     1. Snapshot-First: take_snapshot() como PRIMEIRO passo após cada navegação
     2. Human Usage: NÃO apenas navegar — UTILIZAR como cliente real. Stress test, edge cases.
     3. Design System SOT: verificar .claude/design-system-baseline.local.md PRIMEIRO.
        Se não existe: procurar design system no projecto (CLAUDE.md, docs, componentes,
        página "Desenvolvimento" na app com conta super). Persistir baseline no ficheiro.
        Fallback: inferir das primeiras 3 páginas (confiança 70%).
     4. Interagir com TODOS os elementos do snapshot (não apenas navegar)
     5. "Navigate + title check" = smoke. Funcional = snapshot + interact + verify.
     6. Visual/UI: verificar alinhamento, cores, contraste, menu active state, layout.
     7. Pensamento crítico: edge cases, cross-module impact, fluxos realistas.
     8. Evidência para o DA deve listar CADA interacção concreta.
     ```

6. QA Specialist: verify Chrome DevTools MCP available. If NOT → report to Maestro → STOP.
   **Maestro STOP playbook:** AskUserQuestion "Chrome DevTools MCP indisponível — abortar sessão ou aguardar?".
   Se abortar → shutdown DA + CU Manager (protocolo normal) → terminar skill.
   Se aguardar → manter agentes activos → re-tentar após instrução do user.

### Message Routing (OBRIGATÓRIO — respeitar fluxo)

```
QA Specialist ──SendMessage──→ DA (evidência: ticket ID + interacções + console + network)
                                │
                                ├─ QA-APPROVED ──SendMessage──→ Maestro
                                │                                  │
                                │                      Maestro ──SendMessage──→ CU Manager (status change)
                                │
                                ├─ QA-REJECTED ──SendMessage──→ Maestro
                                │                                  │
                                │                      Maestro decide routing:
                                │                      ├─ Re-test → SendMessage ao QA
                                │                      └─ Status change → SendMessage ao CU Manager
                                │
                                └─ FINDING (new bug) ──SendMessage──→ Maestro
                                                                       │
                                                           Maestro ──SendMessage──→ CU Manager (create ticket)

REGRA: DA NUNCA comunica directamente com CU Manager. Tudo passa pelo Maestro.
REGRA: QA Specialist envia 1 mensagem por ticket ao DA (streaming, não batch).
```

### Timeout Protocol

**DA não responde após QA enviar evidência:**
1. 5 min sem verdict → Maestro envia "Status?" ao DA
2. +2 min sem resposta → Maestro pausa QA, reporta ao user
3. Se user diz continuar → marcar verdict como PENDING-DA, continuar próximo ticket

**QA Specialist não progride (0 páginas em 10 min):**
1. Maestro envia "Status?" ao QA
2. Se QA responde com problema → Maestro resolve (re-login, skip página)
3. Se QA não responde → re-spawnar QA com contexto do último progress

**DA rejeita re-test (2x rejeição no mesmo ticket):**
1. Maestro marca ticket como "blocked-qa"
2. AskUserQuestion: "Ticket {id} rejeitado 2x pelo DA. Continuar para próximo ou investigar?"
3. Continuar com outros tickets, voltar ao blocked no final

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

### Depth Enforcement (Maestro verifica a cada 10 min)

Maestro lê `{REVIEW_DIR}/qa/qa-progress.md` e verifica:

**Indicadores de profundidade CORRECTA (funcional):**
- Entradas com `| {element} | {action} |` (interacções concretas)
- >= 3 interacções por página CRUD
- Evidência de `take_snapshot` nos resultados
- Páginas descobertas via menu (não apenas por URL)

**Indicadores de profundidade INSUFICIENTE:**
- Apenas `| {url} | PASS | console:0 network:0 |` (= smoke)
- Zero interacções (click/fill/select)
- Nenhuma evidência de CRUD ou snapshot
- Todas as páginas navegadas por URL directa (sem menu discovery)

**Acção:**
1. SendMessage ao QA: "Evidência mostra apenas smoke. Re-testar com: take_snapshot, interact, verify."
2. Se após 2 avisos continua → re-spawnar QA com feedback explícito.

### Navigation Audit (Maestro verifica no final)

1. QA deve reportar: "Páginas alcançáveis via UI: {N}. Rotas registadas: {M}. Órfãs: {O}."
2. Se O > 0 → findings de páginas órfãs enviados ao DA
3. Se QA apenas navegou por URL (sem menu discovery) → REJEITAR relatório.

---

## Phase 4: Ticket Validation (tickets at "testing")

For EACH ticket at "testing":
1. QA Specialist: read local `.md` → navigate URL → reproduce original bug scenario → verify FIXED
2. QA Specialist: verify no regressions (console, network, CRUD)
3. QA Specialist → DA (QA-REVIEW): send evidence (ticket ID, URLs, actions, bug status, console, network)
4. DA APPROVED → Maestro envia IMEDIATAMENTE ao CU Manager: status → "deploy to staging" + add `#### QA Results` + `#### Decisões Testing`
5. DA REJECTED → Maestro envia IMEDIATAMENTE ao CU Manager: severity routing:
   - MINOR → status: "ready for dev" (quick-fix)
   - MODERATE/CRITICAL → status: "planning" + Maestro alert

**REGRA STREAMING:** Após CADA DA verdict, Maestro envia ao CU Manager IMEDIATAMENTE.
Não acumular verdicts — cada ticket processado individualmente, em tempo real.

For security/performance tickets: DA does COMBINED QA-REVIEW + CODE-REVIEW (browser evidence + source code).

---

## Phase 5: New Finding Discovery

**TODOS** os findings do QA passam por este fluxo — sem excepções:

Tipos de findings (lista exaustiva):
1. Bugs funcionais (500, CRUD broken, forms, validation, etc.)
2. Páginas órfãs (rotas sem link na UI — do cross-check com routes)
3. Design system inconsistências (desvios do baseline)
4. Visual/UI problemas (alinhamento, cores, menu active state, layout)
5. Edge case failures (stress test, cross-module impact)
6. i18n / acentos / brasileirismos

Fluxo (OBRIGATÓRIO para CADA finding):
1. QA Specialist → DA (FINDING-FILTER): Standard Finding Format
2. DA APPROVED → Maestro envia IMEDIATAMENTE ao CU Manager: create new ticket (status "open")
3. DA REJECTED → Maestro regista no log, no ticket

**PROIBIDO:** Maestro NUNCA cria tickets directamente. Tudo via CU Manager.
**PROIBIDO:** Maestro NUNCA salta o DA. Mesmo findings "factuais" precisam de validação.
**PROIBIDO:** Maestro NUNCA acumula findings. Cada DA verdict → CU Manager em tempo real.

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
