---
name: clickup-code-review:planning
description: Triage ClickUp code review tickets, validate findings against codebase, plan fixes, set dependencies and estimates. Uses decentralised planning — each specialist plans their own area, Investigation + DA validate. Reads from local file cache and detects new ClickUp comments. Use when the user asks to "plan the review fixes", "triage the tickets", "investigate the code review findings", or "prepare tickets for fixing". Use after the audit skill has created tickets.
user_invocable: true
---

# ClickUp Code Review — Planning Skill (v5.2.1)

Triage + validate tickets. Decentralised: each specialist plans their area. Triangle: Specialist + DA + Investigation. Investigation meta-organises waves + dependencies.
**API Patterns:** See `references/clickup-api-patterns.md` for all ClickUp API patterns.

---

## FORBIDDEN (Maestro) — LER PRIMEIRO

1. NUNCA investigar directamente. Maestro é orquestrador, não analista.
2. NUNCA receber finding content de specialists.
3. NUNCA usar `/tmp/`. Tudo em `.claude/code-reviews/` (project-scoped).
4. NUNCA usar `grep -P`. Usar `grep -E`.
5. NUNCA enviar shutdown_request sem ordem explícita do user.
6. NUNCA re-spawnar sem verificar se agente está vivo (SendMessage "Status?").
7. NUNCA fazer side-work durante planning activo. Contexto é finito.
8. NUNCA ler agent .md files. Cada agente lê-se a si próprio.
9. NUNCA spawnar DA ou Investigation DEPOIS dos specialists.
   Ordem: CU Manager → DA + Investigation → Specialists.
10. NUNCA usar ClickUp API directamente. Tudo via CU Manager.
11. NUNCA criar tickets de mensagens de specialists. Só após DA APPROVED.
12. NUNCA GET da descrição para modificar. Compor localmente e PUT.
13. NUNCA spawnar specialists sem contexto transversal (ticket ID + dados CC-PLANNING).
14. NUNCA assumir scope. PERGUNTAR via AskUserQuestion.
15. NUNCA fechar tickets sem validação de specialist + DA.
16. NUNCA gerar bash multi-linha ou com `&&`/`||`/`;`. Cada Bash call = 1 statement.
    Para listar ficheiros: **Glob TOOL**. Para ler: **Read TOOL**.
16. NUNCA fazer trabalho de specialist (source code). DELEGAR.
17. NUNCA shutdown_request sem DA + CU Manager confirmarem sem pendentes.

---

## Shutdown Rules (v5.2.1)

Maestro PODE fechar specialists no FINAL de cada phase. DA + CU Manager persistem toda a sessão.

**Protocolo — ANTES de shutdown_request:**
1. DA: "Tens processos pendentes com {specialist}?" → confirmar sem pendentes
2. CU Manager: "Tens syncs pendentes com {specialist}?" → confirmar sem pendentes
3. SÓ se AMBOS confirmarem → enviar shutdown_request

FORBIDDEN: NUNCA fechar DA ou CU Manager. NUNCA fechar specialists a MEIO de uma phase.

---

## Prerequisites + Pipeline Position

- Tickets em "open" ou "planning" (criados por `/clickup-code-review:audit`)

```
/clickup-code-review:audit     ->  Audit ("open")
/clickup-code-review:planning  ->  ESTE SKILL (open -> planning -> ready for dev)
/clickup-code-review:fix       ->  Execute (ready for dev -> testing)
/clickup-code-review:testing   ->  Validate (testing -> deploy to staging)
```

---

## Spawn Order (MANDATORY)

**Step 0 — TeamCreate (OBRIGATÓRIO — sem isto SendMessage não funciona):**
```
TeamCreate(team_name="cc-planning-{shortname}-{date}", description="Code Review planning phase")
```
TODOS os agentes spawned com `team_name` e `name` para comunicação via SendMessage.

1. CU Manager: `Task(team_name="cc-planning-...", name="cu-manager")` → config + status mapping + folder tree → READY + paths
2. DA: `Task(team_name="cc-planning-...", name="da")` → PLANNING-REVIEW mode
   Investigation: `Task(team_name="cc-planning-...", name="investigation")` → PLANNING mode
   → aguardar READY de AMBOS
3. Specialists: `Task(team_name="cc-planning-...", name="{specialist}")` → por área, PLANNING mode — SÓ após DA + Investigation READY

**PRE-SPAWN GATE:** DA não spawned OU Investigation não spawned? STOP → spawn ambos → aguardar READY de AMBOS → então specialists.

**PLUGIN_ROOT:** Obter via `Bash "echo $CLAUDE_PLUGIN_ROOT"` ANTES de spawnar specialists.
Incluir em CADA spawn: `"Plugin root: {PLUGIN_ROOT} — lê o teu agent .md completo em {PLUGIN_ROOT}/agents/{agent-name}.md."`

---

## Phase 0: Configuration Check

0. **Hook guard activation:** `touch ~/.clickup-review-active` (enables plugin hooks for this session)

```bash
if ! grep -q 'code-reviews/' .gitignore 2>/dev/null; then
  echo '.claude/code-reviews/' >> .gitignore
fi
```

1. Verificar `CLICKUP_API_TOKEN`, `List ID`, `Shortname` (MEMORY.md) — falta algum? → setup
2. Local cache: verificar `.claude/code-reviews/` da fase audit
3. Resume: CU Manager verifica tickets já em "planning" → apresentar ao user
4. **Cache Reconciliation (1x/sessão):** CU Manager: RECONCILE CACHE → report divergências

---

## Phase 0B: Ticket Selection

1. CU Manager: fetch tickets em "open" + "planning"
2. Auto-detect: se audit foi na mesma sessão + cache hoje → avançar com todas (skip AskUserQuestion)
3. Caso contrário: AskUserQuestion (multiSelect): Todas / Security / Backend / Frontend / Quality / Complexity / QA
4. Apresentar scope: "Novos (open): {N}. Em progresso: {M}. Total: {count}."
5. AskUserQuestion: "Avançar com a investigação?"

---

## Phase 1: Decentralised Planning (Triangle Validation)

Para CADA ticket: CU Manager: comment check + read local .md + status → "planning"

**Triangle flow:**
```
Specialist: 2 abordagens A vs B + trade-offs → SendMessage para DA + Investigation
DA (PLANNING-REVIEW): valida → VALID/NEEDS-CHANGE/INVALID → specialist + Maestro
Investigation: re-lê código, cross-area impact → verdict → specialist + Maestro
Consenso: DA VALID + Investigation VALID → plano aprovado
NEEDS-CHANGE: specialist revisa, max 2 rounds. INVALID: revisa ou ticket fechado.
```

Paralelismo: áreas diferentes em paralelo. Mesma área >15 tickets → sub-batches.

---

## Phase 2: Meta-Organisation (Investigation + DA Ping-Pong)

Após TODOS os specialists: Investigation analisa todos os planos validados:
1. Cross-area dependencies + file conflicts + execution order
2. Ticket consolidation (mesma área + Medium/Low + ≤5 ficheiros → propor merge)
3. Wave grouping (sem conflitos intra-wave) + routing por specialist

Investigation → DA: wave plan proposto → ping-pong (max 3 rounds) → plan final ao Maestro.

---

## Phase 3: ClickUp Updates (via CU Manager)

Para CADA ticket validado. **Audit sections são IMUTÁVEIS** (NUNCA modificar originais).

CU Manager adiciona ao local `.md`:

```markdown
#### Planeamento
- **Agente:** {specialist}
- **Abordagem:** {A — escolhida}
- **Abordagem {outra} (rejeitada):** {razão}
- **QA:** {unit/e2e/manual}
- **Ficheiros:** {lista}
- **Dependências:** {nenhuma / ticket_id}
- **Wave:** {1/2/...}
- **Estimativa:** {Xm}

##### Correcção Sugerida (Actualizado após Planeamento)
{versão refinada — tem PRECEDÊNCIA sobre original}

##### Como Testar (Actualizado após Planeamento)
{versão refinada — tem PRECEDÊNCIA}

#### Decisões Planning
- **DA (PLANNING-REVIEW):** {VALID/NEEDS-CHANGE round N} — "{razão}"
- **Investigation:** {VALID/PARTIAL} — "{cross-area impact}"
- **Maestro:** aprovado, Wave {N}
```

**Sub-sections `#####`** só se planning MODIFICA o original. Se inalterado → omitir.
**FORWARD-REFERENCE:** Se `#####` existirem → nota no TOPO do original: `*(ver versão actualizada em Planeamento abaixo)*`

CU Manager: PUT (`markdown_description`) + frontmatter (`status: ready for dev`) + set deps ClickUp.
Merged tickets: fechar B + comment "Consolidado com {A}" + dependência ClickUp + enriquecer A.

---

## Phase 4: Summary

```markdown
## Planning Summary
### Wave Plan | Wave | Tickets | Priority | Dependencies |
### Statistics: Total {N} | Valid {X} | Invalid {Y} | Merged {M} | Severity changes {Z}
### Next steps: /clickup-code-review:fix
```

---

## Checklist (Maestro verifica ANTES de reportar ao user)

- [ ] Gitignore: `.claude/code-reviews/` presente
- [ ] CU Manager spawned, config validada, RECONCILE CACHE executado
- [ ] Local cache detectado, sessão identificada
- [ ] Comments fetched para TODOS os tickets (via CU Manager)
- [ ] PRE-SPAWN GATE: DA + Investigation spawned ANTES dos specialists
- [ ] Cada specialist recebeu SÓ os tickets da sua área
- [ ] Triangle validation: DA + Investigation verdicts para todos os planos
- [ ] Investigation meta-organização: waves, deps, merges
- [ ] Todos os tickets válidos: `#### Planeamento` + `#### Decisões Planning`
- [ ] Todos os `.md` locais PUT para ClickUp com frontmatter actualizado
- [ ] Dependências definidas no ClickUp
- [ ] Hook guard deactivated: `rm -f ~/.clickup-review-active`
- [ ] Tickets ao status correcto ("ready for dev" ou "Closed")
- [ ] Merged tickets: B fechado, A enriquecido
- [ ] Wave plan documentado e apresentado ao user
