---
name: clickup-code-review:audit
description: Use when performing comprehensive codebase audits with ClickUp ticket creation, full project code reviews with ClickUp tracking, or quality assessments that need multi-agent analysis. This skill should be used when the user asks to "audit the codebase", "run a code review and create tickets", "security and performance audit with ClickUp", or "launch a multi-agent code review".
user_invocable: true
---

# ClickUp Code Review — Audit Skill (v5.1.1)

Multi-agent audit: specialists → DA filters → CU Manager creates tickets. No fixes applied.
**API Patterns:** See `references/clickup-api-patterns.md` for all ClickUp API patterns.

---

## FORBIDDEN (Maestro) — LER PRIMEIRO

1. NUNCA receber finding content. Só paths e verdicts curtos (~80 chars).
2. NUNCA relay findings entre agentes. Specialists → DA é directo.
3. NUNCA enviar batches ao CU Manager. 1 finding de cada vez.
4. NUNCA ler finding files. Para status → pedir ao DA via SendMessage.
   EXCEPÇÃO: deadlock após 3 rounds + specialist sem resposta → Maestro arbitra (0-3x por audit).
5. NUNCA ler security coverage assessment file. DA envia RESUMO via SendMessage.
6. NUNCA re-spawnar sem verificar se agente está vivo (SendMessage "Status?").
7. NUNCA usar `grep -P`. Usar `grep -E`.
8. NUNCA enviar shutdown_request sem ordem explícita do user.
9. NUNCA fazer side-work durante audit activo. Contexto é finito.
10. NUNCA usar `/tmp/`. Tudo em `.claude/code-reviews/` (project-scoped).
11. NUNCA ler agent .md files. Cada agente lê-se a si próprio.
12. Keepalives só para audits >15 tickets. <10 tickets: 1 status update por fase.
13. NUNCA assumir scope. Se o user não especificou, PERGUNTAR via AskUserQuestion.
14. NUNCA fechar tickets sem validação de specialist + DA.
15. NUNCA fazer trabalho de specialist (source code, análise). DELEGAR.
16. NUNCA enviar shutdown_request sem DA e CU Manager confirmarem sem pendentes.
17. NUNCA gerar bash multi-linha ou com `&&`/`||`/`;`. Cada Bash call = 1 statement.
    Para listar ficheiros: usar **Glob TOOL**. Para ler: usar **Read TOOL**.

---

## Shutdown Rules (v5.1.1)

Maestro PODE fechar specialists no FINAL de cada phase. DA + CU Manager persistem toda a sessão.

**Protocolo — ANTES de shutdown_request:**
1. DA: "Tens processos pendentes com {specialist}?" → confirmar sem pendentes
2. CU Manager: "Tens syncs pendentes com {specialist}?" → confirmar sem pendentes
3. SÓ se AMBOS confirmarem → enviar shutdown_request

FORBIDDEN: NUNCA fechar DA ou CU Manager. NUNCA fechar specialists a MEIO de uma phase.

**Fim de sessão (user termina):** shutdown_request a todos → TeamDelete() para limpar equipa.

---

## Prerequisites + Pipeline Position

```
/clickup-code-review:audit     ->  ESTE SKILL (cria tickets em "open")
/clickup-code-review:planning  ->  Triage (open -> ready for dev)
/clickup-code-review:fix       ->  Execute (ready for dev -> testing)
/clickup-code-review:testing   ->  Validate (testing -> deploy to staging)
```

---

## Phase 0: Configuration Check

0. **Hook guard activation:** `touch ~/.clickup-review-active` (enables plugin hooks for this session)

```bash
if ! grep -q 'code-reviews/' .gitignore 2>/dev/null; then
  echo '.claude/code-reviews/' >> .gitignore
fi
```

1. Read MEMORY.md → `Workspace ID`, `List ID`, `Shortname`
2. Check `$CLICKUP_API_TOKEN` (starts with `pk_`)
3. Se ALL presentes → validate via `GET /team` → proceed
4. Se missing → `/clickup-code-review:setup` só para itens em falta
5. Never block — se user recusar setup, avisar e continuar
6. **Cache Reconciliation (1x/sessão):** CU Manager: RECONCILE CACHE → report divergências

---

## Phase 0B: Category Selection

AskUserQuestion (multiSelect, 2 perguntas — default: todas):
- Pergunta 1: Security (opus) / Backend & Perf / Frontend / Quality
- Pergunta 2: Complexity / QA Unit / QA E2E

| Category | Agent | model |
|----------|-------|-------|
| Security | security-specialist | opus |
| Backend & Perf | backend-specialist | sonnet |
| Frontend | frontend-specialist | sonnet |
| Quality | quality-specialist | sonnet |
| Complexity | code-simplifier | sonnet |
| QA Unit/E2E | qa-specialist | sonnet |

DA + CU Manager correm SEMPRE (independente de selecção).

---

## Phase 1: Team + Spawn (MANDATORY ORDER)

**Step 1.0 — TeamCreate (OBRIGATÓRIO — sem isto SendMessage não funciona):**
```
TeamCreate(team_name="cc-review-{shortname}-{date}", description="Code Review audit")
```
TODOS os agentes spawned com `team_name` para comunicação via SendMessage.
Sem TeamCreate → agentes ficam isolados → SendMessage falha → audit quebra.

**Directory variables (CU Manager cria + partilha com todos):**
```
PLUGIN_ROOT = $CLAUDE_PLUGIN_ROOT   (obter via: Bash "echo $CLAUDE_PLUGIN_ROOT")
REVIEW_DIR  = ".claude/code-reviews/{main_task_id} - CC Review YYYY-MM-DD"
FINDINGS_DIR = "{REVIEW_DIR}/findings"
PROGRESS_DIR = "{REVIEW_DIR}/progress"
```

**Step 1.1 — CU Manager:**
```
Task(subagent_type="clickup-code-review:clickup-manager", team_name="cc-review-...", name="cu-manager", ...)
```
Cria main task + area subtasks + ENTIRE local folder tree → reporta paths.
**GATE:** AGUARDAR confirmação do CU Manager com FINDINGS_DIR + PROGRESS_DIR antes de avançar.
Se não receber paths em < 2 min → SendMessage "Status?" ao CU Manager (repetir 1x).
Se ainda sem resposta → ESCALATE: PARAR audit, reportar ao user, aguardar instrução.

**Step 1.2 — DA (spawnar ANTES dos specialists):**
```
Task(subagent_type="clickup-code-review:devils-advocate", team_name="cc-review-...", name="da", ...)
```
MODE: FINDING-FILTER + area_task_ids + FINDINGS_DIR + PROGRESS_DIR → aguarda READY.

**Step 1.3 — Specialists (spawnar DEPOIS do DA estar READY):**
```
Task(subagent_type="clickup-code-review:{specialist}", team_name="cc-review-...", name="{agent-name}", ...)
```

**Specialist spawn template (MANDATORY — incluir em CADA spawn):**
```
"Tu és o {agent-name}. MODE: AUDIT.
Team: cc-review-{shortname}-{date}. DA name: "da". CU Manager name: "cu-manager".

Nº1: Escreve cada finding para {FINDINGS_DIR}/{agent-name}-{n}.md (pasta já criada — não recriar).
Nº2: Notifica DA via SendMessage(recipient="da"): "Valida {FINDINGS_DIR}/{file}"
Nº3: NUNCA envies findings ao Maestro. Destinatário é o DA.
Nº4: Se DA te questionar → PÁRA e RESPONDE IMEDIATAMENTE (prioridade absoluta sobre novos findings).
Nº5: Progresso → {PROGRESS_DIR}/agent-{agent-name}-progress.md

Projecto: {shortname} | Stack: {stack info}
Plugin root: {PLUGIN_ROOT}
Lê o teu agent .md completo em {PLUGIN_ROOT}/agents/{agent-name}.md. Começa análise."
```

---

## Phase 2-3: Audit + DA Filtering

Specialists → findings files → notificam DA → DA lê + verdict ao Maestro (~80 chars).

**GATE RULE (NON-NEGOTIABLE):** SÓ após DA enviar `APPROVED {path}` → instruir CU Manager.
- REJECTED → log, sem ticket
- ESCALATED → Maestro pinga specialist, arbitra, decide

**SendMessage:** paths e verdicts (~80 chars) — NUNCA finding content, NUNCA batches.
Sem DA verdict >2 min → SendMessage "Status?" ao DA.
DA não responder antes do próximo turn → ESCALATE: PARAR dispatch de novos findings, reportar ao user, aguardar instrução.

---

## Phase 4: Ticket Creation (STREAMING — 1 at a time)

`"Cria ticket de {FINDINGS_DIR}/security-1.md — area: {area}, parent: {area_task_id}"`

CU Manager: lê → credential scan → POST → cria `{REVIEW_DIR}/{area}/{task_id}.md` → reporta task_id (~20 chars).

---

## Phase 5: Summary (ANTI-HALLUCINATION)

Summary é REPORT do ClickUp, não recollection.
1. CU Manager: `GET /list/{LIST_ID}/task?subtasks=true&include_markdown_description=true`
2. Summary EXCLUSIVAMENTE de dados reais. Cada finding com task_id ClickUp.
3. Apresentar → ESPERAR instrução do user. NUNCA shutdown autonomamente.

---

## Maestro Checklist (v5.1.1)

- [ ] Gitignore: `.claude/code-reviews/` presente
- [ ] CU Manager spawned, config validada, RECONCILE CACHE executado
- [ ] AskUserQuestion: category selection
- [ ] CLAUDE.md lido: stack, conventions, security rules
- [ ] CU Manager: main task + area subtasks + ENTIRE folder tree criados
- [ ] FINDINGS_DIR + PROGRESS_DIR recebidos do CU Manager
- [ ] DA spawned (MODE: FINDING-FILTER). READY confirmado.
- [ ] Specialists spawned com template OBRIGATÓRIO (FINDINGS_DIR + PROGRESS_DIR incluídos)
- [ ] GATE: NUNCA criar tickets de specialist messages (só DA APPROVED)
- [ ] NUNCA ler finding files (pedir ao DA via SendMessage)
- [ ] NUNCA side-work durante audit
- [ ] Keepalive (>15 tickets only): sem DA verdict >2 min → "Status?" ao DA
- [ ] Liveness check ANTES de qualquer re-spawn
- [ ] CU Manager actualizou area subtasks após todos os findings processados
- [ ] Summary gerado de dados reais (via CU Manager query)
- [ ] Summary apresentado ao user → aguardar instrução
- [ ] NUNCA shutdown sem ordem explícita do user
- [ ] Hook guard deactivated: `rm -f ~/.clickup-review-active`
