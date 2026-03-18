---
name: clickup-code-review:fix
description: Implement fixes for validated ClickUp code review tickets. Handles branching, wave execution, DA code review with evidence gates, and status updates through "deploy to staging". Uses ClickUp Manager for ALL API operations. Checks for new ClickUp comments before each fix. Use when the user asks to "fix the review tickets", "implement the planned fixes", "execute the code review fixes", or "start fixing wave 1". Use after planning has prepared tickets.
user_invocable: true
---

# ClickUp Code Review — Fix Skill (v5.1.1)

Execute planned fixes for validated tickets. Serial queue — 1 specialist at a time. DA CODE-REVIEW + evidence gate + commit per ticket.

**BEFORE Phase 1:** Read `references/fix-protocol.md` for per-ticket cycle, evidence gate details, commit format.
**API Patterns:** See `references/clickup-api-patterns.md` for all ClickUp API patterns.

---

## FORBIDDEN (Maestro) — LER PRIMEIRO

1. NUNCA implementar fixes directamente. Specialists implementam, DA revê, Maestro commita.
2. NUNCA usar `/tmp/`. Tudo em `.claude/code-reviews/`.
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

---

## Shutdown Rules (v5.1.1)

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
4. Specialists: Task(team_name="cc-fix-...", name="{specialist}") → per wave, 1 at a time (Serial Queue)
```

---

## Serial Queue (v5.1.1)

**1 specialist de cada vez. Zero staging compartilhado.**

1. Maestro despacha 1 ticket para 1 specialist
2. Specialist implementa + stage + envia diff ao DA
3. DA revê → APPROVED / REQUEST-CHANGES
4. Se APPROVED → Maestro commita → staging limpo
5. Se REQUEST-CHANGES → specialist corrige → re-stage → DA round 2
6. Só após commit (ou skip) → despachar PRÓXIMO ticket
7. Wave grouping mantém-se para ordenação/dependências

**FORBIDDEN (Maestro):**
- NUNCA spawnar 2+ specialists simultaneamente
- NUNCA pre-dispatch enquanto DA revê ou staging ocupado
- NUNCA qualquer variante de staging paralelo

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

1. Gitignore: verify `.claude/code-reviews/` in `.gitignore`
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

## Phase 1-N: Wave Execution (Serial — 1 ticket at a time)

**Full per-ticket cycle in `references/fix-protocol.md`.** Summary:

**PLUGIN_ROOT:** Obter via `Bash "echo $CLAUDE_PLUGIN_ROOT"` uma vez no início. Incluir em CADA spawn de specialist.

For EACH ticket in current wave:
1. CU Manager: comment check → assess impact → proceed/skip/adapt
2. Maestro provides FULL context to specialist: ticket ID + Problema + Impacto + Planeamento (updated sub-sections have PRECEDENCE) + Plugin root: {PLUGIN_ROOT}
3. CU Manager: status → "in progress"
4. Specialist: implements fix + stages + sends diff to DA (CODE-REVIEW template in fix-protocol.md)
5. CU Manager: status → "code review"
6. DA APPROVED → specialist reports to Maestro → `git commit`
   DA REQUEST-CHANGES → specialist corrects → re-stage → new diff to DA (max 2 rounds)
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

- [ ] Gitignore checked for `.claude/code-reviews/`
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
