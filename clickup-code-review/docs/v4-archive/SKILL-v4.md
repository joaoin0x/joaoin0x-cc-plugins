---
name: clickup-code-review
description: "[LEGACY v4 — use clickup-code-review:audit instead] This skill is kept for backward compatibility. The v5.0 audit skill at skills/audit/SKILL.md replaces this entirely."
user_invocable: true
---

# ClickUp Code Review (Legacy v4 — Redirects to :audit)

**This skill has been superseded by `/clickup-code-review:audit` in v5.0.**

Run `/clickup-code-review:audit` instead. This file is kept only so that existing invocations of `/clickup-code-review` still work.

The `agent-prompts/` directory below contains v4 reference prompts (read-only, not used by v5 agents).

## Overview

Orchestrates 8 specialized agents in waves: parallel review, skeptical filtering (streaming), then ClickUp ticket creation. Findings go through a Devil's Advocate before becoming tickets — only real, evidence-backed issues get tracked.

**No fixes are applied.** This is audit-only. The senior decides what to fix and when.

**API Patterns:** See `references/clickup-api-patterns.md` for all ClickUp API interaction patterns (token extraction, response handling, description read/write, rate limiting).

## When to Use

- Full project code review with ClickUp tracking
- Pre-release quality audit
- Periodic codebase health check
- Security/performance audit with ticket management

## Phase 0 — Configuration Check

Before creating the team or launching any agents, verify all required configuration.

### Gitignore check (MANDATORY)

```bash
if ! grep -q 'code-reviews/' .gitignore 2>/dev/null; then
  echo '.claude/code-reviews/' >> .gitignore
fi
```

### Required Configuration

| Setting | Source | How to check |
|---------|--------|-------------|
| API Token | `$CLICKUP_API_TOKEN` env var | Check if set and starts with `pk_` |
| Workspace ID | Project MEMORY.md | Look for `Workspace ID:` |
| List ID | Project MEMORY.md | Look for `List ID:` |
| Shortname | Project MEMORY.md | Look for `Shortname:` |

### Phase 0 Flow

1. Read project's MEMORY.md -> extract `Workspace ID`, `List ID`, `Shortname`
2. Check `$CLICKUP_API_TOKEN` environment variable
3. **If ALL present** -> validate token with `curl -s -X GET -H "Authorization: $CLICKUP_API_TOKEN" "https://api.clickup.com/api/v2/team"` -> if valid, proceed
4. **If something is missing** -> run setup ONLY for the missing items (invoke `/clickup-code-review:setup` wizard for the specific missing step)
5. **Never block** — if the user refuses setup, warn them and proceed

## Phase 0B — Category Selection

After config is validated, ask the user which review categories to run. Use `AskUserQuestion` with `multiSelect: true`.

**Default:** All categories selected. The user deselects what they don't need.

Use a single `AskUserQuestion` call with 2 multi-select questions (max 4 options each):

```
AskUserQuestion:
  questions:
    - question: "Code analysis — which categories?"
      header: "Analysis"
      multiSelect: true
      options:
        - label: "Security"
          description: "Vulnerabilities, auth, IDOR, injection, SSRF (opus)"
        - label: "Backend & Perf"
          description: "N+1, caching, query optimization, API design"
        - label: "Frontend"
          description: "WCAG, Blade templates, Bootstrap, JS, accessibility"
        - label: "Quality"
          description: "PSR-12, SOLID, dead code, naming, type hints"

    - question: "Testing & complexity — which categories?"
      header: "Testing"
      multiSelect: true
      options:
        - label: "Complexity"
          description: "Over-engineering, god classes, method extraction"
        - label: "QA Unit"
          description: "Missing tests, coverage gaps, test quality"
        - label: "QA E2E"
          description: "Browser testing, CRUD workflows, UI regressions"
```

**Category -> Agent mapping:**

| Category | Agent | subagent_type | model | Prompt file |
|----------|-------|--------------|-------|-------------|
| Security | security-agent | cybersecurity-expert | opus | agent-prompts/security-agent.md |
| Backend & Performance | backend-perf-agent | backend-architect | sonnet | agent-prompts/backend-perf-agent.md |
| Frontend | frontend-agent | frontend-expert | sonnet | agent-prompts/frontend-agent.md |
| Quality | quality-agent | backend-architect | sonnet | agent-prompts/quality-agent.md |
| Complexity | code-simplifier | clickup-code-review:code-simplifier | sonnet | agent-prompts/code-simplifier.md |
| QA Unit | qa-unit-agent | qa-testing-expert | sonnet | agent-prompts/qa-unit-agent.md |
| QA E2E | qa-e2e-agent | qa-testing-expert | sonnet | agent-prompts/qa-e2e-agent.md |

**Only spawn agents for selected categories.** The DA always runs (it filters whatever comes in).

## Architecture

**CRITICAL: Role Separation — Maestro is an ORCHESTRATOR, never an implementer.** The Maestro reads context, spawns agents, creates ClickUp tickets, and presents summaries. It NEVER reads source code to analyze it directly, NEVER writes findings itself, and NEVER bypasses the DA. All code analysis is done by specialist agents. All quality filtering is done by the DA.

```
MAESTRO (you, opus)
|-- Reads context, asks user if missing info
|-- Category selection (user picks which agents to run)
|-- Creates team, spawns selected agents + DA
|-- GATE: Only creates tickets after DA APPROVED verdict (never from specialist directly)
|-- Sends keepalive messages to DA during long processing
|-- Receives final summary from specialists + DA verdicts
|
|-> security-agent      (opus, cybersecurity-expert)  --|
|-> backend-perf-agent  (sonnet, backend-architect)   --|
|-> frontend-agent      (sonnet, frontend-expert)     --|--> SendMessage findings DIRECTLY to DA
|-> quality-agent       (sonnet, backend-architect)   --|    (one finding per message, streamed)
|-> code-simplifier     (sonnet, clickup-code-review) --|
|-> qa-unit-agent       (sonnet, qa-testing-expert)   --|
|-> qa-e2e-agent        (sonnet, qa-testing-expert)   --|
|                                                       |
'-> devils-advocate     (opus, clickup-code-review:devils-advocate)
    MODE: FINDING-FILTER
    Receives findings directly from specialists (NOT via Maestro)
    Streams verdicts: APPROVED/REJECTED -> Maestro creates ticket immediately
```

**CRITICAL: Specialists send findings DIRECTLY to `devils-advocate`, NOT to Maestro.** The Maestro only receives DA verdicts (APPROVED/REJECTED) and final summaries from specialists. This eliminates the Maestro as a bottleneck in the finding pipeline.

## Flow

```
1. Read context (MEMORY.md, CLAUDE.md). Ask user if missing.
2. Category selection (user picks agents).
3. TeamCreate + spawn selected agents + DA.
4. Wave 1: Parallel review — specialists send findings DIRECTLY to DA (one at a time, streamed).
5. Wave 2: DA filters findings and streams verdicts to Maestro.
   APPROVED -> Maestro creates ticket. REJECTED -> Maestro logs rejection.
   Maestro sends keepalive to DA every ~2 min during long filtering.
6. Maestro creates ClickUp tickets + local .md files progressively as approvals arrive.
7. Specialists send final summary to BOTH DA and Maestro when done.
8. Security Verification (conditional): If DA reports coverage gaps.
9. Data-driven summary: Query ClickUp, build from real tickets.
```

### Wave 1: Parallel Review

Spawn only the review agents selected by the user in Phase 0B. Each gets a tailored prompt from `agent-prompts/`.

**How to load prompts:** Read each file with the Read tool from the `agent-prompts/` directory relative to this SKILL.md, then pass its content as the `prompt` parameter to the Agent tool. Prepend project-specific context (shortname, stack info from CLAUDE.md).

**Inter-agent communication:** Agents can SendMessage to each other for context. E.g., security-agent asks backend-perf-agent about a query pattern.

### Wave 2: Devil's Advocate (Streaming)

Spawn the devils-advocate agent with `MODE: FINDING-FILTER` instruction. The DA receives findings DIRECTLY from specialist agents (not via Maestro) and processes them as they arrive — **no batching**:

1. Receives a finding directly from a specialist agent via SendMessage
2. Quick assess: obvious approve/reject -> verdict immediately to Maestro
3. Uncertain: questions the reviewer directly (max 3 debate rounds via SendMessage)
4. Verdict sent to Maestro as soon as decided
5. Maestro can start creating ClickUp tickets while DA processes remaining findings

**Verdict types:**
- **APPROVED** — real issue, Maestro creates ticket
- **REJECTED** — false positive, duplicate, or cosmetic
- **REJECTED after consensus** — debate happened, reviewer conceded
- **REJECTED by DA** — max debate rounds, DA decided evidence insufficient

**Keepalive:** During long DA processing (e.g., 79 findings), Maestro sends periodic messages to DA: "Still processing, continue." every ~2 minutes. This prevents idle timeout.

### CRITICAL GATE: DA Approval Required Before Ticket Creation

**NEVER create a ClickUp ticket until the DA has explicitly sent an APPROVED verdict for that specific finding.**

Specialists send findings DIRECTLY to the DA. The Maestro does NOT see raw findings — it only receives DA verdicts. The Maestro MUST:
1. **WAIT for DA verdict** (APPROVED/REJECTED) — findings go specialist → DA, not through Maestro
2. Only if DA sends `APPROVED` -> create ClickUp ticket
3. If DA sends `REJECTED` -> log rejection, do NOT create ticket

**What this means in practice:** The Maestro does NOT maintain a finding queue. It simply processes DA verdicts as they arrive. Each verdict contains the full finding text + DA assessment. The Maestro NEVER creates tickets from specialist agent messages directly — it may not even see them.

### Wave 3: ClickUp Tickets + Local Cache (Progressive)

Create tickets as DA APPROVALS stream in. Don't wait for all findings to be processed — but NEVER create a ticket without DA approval first.

**Hierarchy:**

```
CC Review YYYY-MM-DD                     <- main task (create first)
|-- Security                             <- area subtask (create upfront)
|   |-- Finding title                    <- finding subtask (create as approved)
|   '-- ...
|-- Performance
|   '-- ...
|-- Quality / Complexity / Frontend / QA
'-- ...
```

#### Step 1: Create main task + ALL area subtasks upfront

1. Create main task in ClickUp: `CC Review YYYY-MM-DD` → get `main_task_id`
2. Create ALL area subtasks for selected categories (even areas that may have zero findings) → get `area_task_id` per category
3. **Create entire local folder tree:**

```bash
REVIEW_DIR=".claude/code-reviews/${main_task_id} - CC Review YYYY-MM-DD"
mkdir -p "$REVIEW_DIR"

# Create _main.md with frontmatter
cat > "$REVIEW_DIR/_main.md" <<'EOF'
---
task_id: ${main_task_id}
status: open
last_synced: ${ISO_TIMESTAMP}
last_comment_id: ""
---
EOF

# For EACH selected area:
AREA_DIR="$REVIEW_DIR/${area_task_id} - ${AREA_NAME}"
mkdir -p "$AREA_DIR"

cat > "$AREA_DIR/_area.md" <<'EOF'
---
task_id: ${area_task_id}
area: ${AREA_NAME}
status: open
last_synced: ${ISO_TIMESTAMP}
last_comment_id: ""
---
EOF
```

Empty area folders at the end = good sign (no findings in that category).

**Area subtask naming:** Use ONLY the category name — e.g., `Security`, `Performance`, `Quality`. Do NOT append finding counts or stats.

#### Step 2: Create finding tickets progressively (as DA approves)

### Ticket Creation (2-Step: POST name → PUT full description + Local Cache)

Each finding ticket requires **2 API calls**: POST to create (get task_id), then PUT with COMPLETE description including Issue Name. **Additionally, a local `.md` file is created as the composition surface.**

**WHY 2 steps instead of 1:** The Issue Name block needs the real `task_id`, which only exists after creation. By composing the FULL description locally (never reading it back from ClickUp), we eliminate the round-trip GET that caused description wipes in v3.1.0 and v4.0.0-beta.

**Step 1 — POST: Create task with name only**

```bash
JSON_PAYLOAD=$(python3 -c "
import json
print(json.dumps({
    'name': '${SHORTNAME} - ${FINDING_TITLE}',
    'parent': '${AREA_TASK_ID}',
    'priority': ${PRIORITY_INT}
}))
")

RESPONSE=$(curl -s -X POST \
  -H "Authorization: ${CLICKUP_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD" \
  "https://api.clickup.com/api/v2/list/${LIST_ID}/task")

FINDING_ID=$(echo "$RESPONSE" | grep -o '"id":"[^"]*"' | head -1 | cut -d'"' -f4)
```

**Step 2 — Create local `.md` file with full description**

Compose the description in a local file FIRST. This is the composition surface — if PUT fails, content is preserved.

```bash
FINDING_FILE="${AREA_DIR}/${FINDING_ID}.md"

cat > "$FINDING_FILE" <<'DESCEOF'
---
task_id: ${FINDING_ID}
area: ${AREA_NAME}
severity: ${SEVERITY}
priority: ${PRIORITY_INT}
status: open
last_synced: ""
last_comment_id: ""
---
- **Severidade:** ${SEVERITY}
- **Confianca:** ${CONFIDENCE}%
- **Ficheiro:** `${FILE_PATH}`
- **Rota:** `${ROUTE}`
- **Estimativa:** ${ESTIMATE}

#### Problema
${PROBLEMA_TEXT}

#### Impacto
${IMPACTO_TEXT}

#### Evidencia
```php
${EVIDENCE_CODE}
```

#### Correcao Sugerida
- [ ] ${FIX_STEP_1}
- [ ] ${FIX_STEP_2}
- [ ] ${FIX_STEP_3}

#### Como Testar
- [ ] ${TEST_STEP_1}
- [ ] ${TEST_STEP_2}
- [ ] ${TEST_STEP_3}

---
#### Nome do Issue
```
${FINDING_ID} - ${SHORTNAME} - ${FINDING_TITLE}
```
DESCEOF
```

**Step 3 — PUT: Push local file content to ClickUp**

**CRITICAL — Strip frontmatter before PUT:** Local `.md` files contain YAML frontmatter (`---` delimited) that is LOCAL-ONLY metadata. It must NEVER be sent to ClickUp. Always extract only the content AFTER the second `---` delimiter.

```bash
# Extract content AFTER YAML frontmatter (after the SECOND --- delimiter)
DESC_CONTENT=$(awk '/^---$/{n++; next} n>=2' "$FINDING_FILE")

JSON_PAYLOAD=$(python3 -c "
import json, sys
desc = sys.stdin.read()
print(json.dumps({'markdown_description': desc}))
" <<< "$DESC_CONTENT")

curl -s -X PUT -H "Authorization: ${CLICKUP_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD" \
  "https://api.clickup.com/api/v2/task/${FINDING_ID}"
```

**Step 4 — Update frontmatter with sync timestamp**

Update `last_synced` in the local `.md` file's frontmatter to the current ISO timestamp.

**CRITICAL: The description is composed 100% locally. We NEVER GET the description back from ClickUp to modify it. The local `.md` file IS the composition surface.**

**If PUT fails:** Content is preserved in the local file. Maestro logs the failure and can retry later. No data loss.

**Markdown checklists:** `- [ ]` items in `Correcao Sugerida` and `Como Testar` render as interactive checkboxes in ClickUp. Zero native checklist API calls.

**Only these fields:** POST uses `name`, `parent`, `priority`. PUT uses `markdown_description`.
**NEVER include:** `tags`, `assignees`, `custom_fields`, `due_date`, `start_date`

**ClickUp formatting rule:** NO blank lines after h4 titles. Content follows immediately: `#### Problema\n{content}` (1 newline), NOT `#### Problema\n\n{content}` (2 newlines).

### Idempotency — Fuzzy Match Before Creating

Before creating each finding ticket, check for existing tickets in the area subtask:

```bash
# Fetch all subtasks of the area task
RESPONSE=$(curl -s -X GET -H "Authorization: ${CLICKUP_API_TOKEN}" \
  "https://api.clickup.com/api/v2/task/${AREA_TASK_ID}?subtasks=true&include_markdown_description=true")
```

Compare new finding title against existing ticket titles:
- **Exact match** -> skip entirely
- **Similar match** (same file reference + same issue type + overlapping keywords) -> log warning to Maestro, skip creation, note: "Possivel duplicado: {new} ~ {existing}"
- **No match** -> create normally

### Area Subtask — Final Description Format

After all findings are processed, update each area subtask description AND local `_area.md`:

```markdown
## {Area Name} — Summary

**Approved:** {count} findings (created as subtasks below)
**Rejected:** {count} findings (filtered by Devil's Advocate)

### Rejected Findings

| Finding | Verdict | Razao |
|---------|---------|-------|
| {SHORTNAME} - Title | False positive | DA explanation |
| {SHORTNAME} - Title | Cosmetic / by-design | DA explanation |

_Findings rejeitados nao tem subtask — documentados aqui para rastreabilidade._
```

**Local cache:** Write this same content to the `_area.md` file in the area folder (after the YAML frontmatter). **Strip frontmatter before PUT** — extract content after the second `---` delimiter, then PUT to ClickUp. Update `last_synced` in frontmatter.

## Phase: Security Verification (Conditional)

**Only runs if DA reports coverage gaps in the Security Coverage Assessment.**

When the DA's final message includes a Security Coverage Assessment with "Recommendation: Re-scan needed":

1. Spawn a fresh `cybersecurity-expert` agent (opus model)
2. Provide: list of already-found security findings + DA's gap assessment
3. Instruction: "Audit the same codebase. Report ONLY findings NOT already in the approved list."
4. New findings go through normal DA filtering (FINDING-FILTER mode) before ticket creation
5. If DA reports "Coverage adequate" -> skip this phase entirely

**Cost:** Phase 1 (DA assessment) = zero extra. Phase 2 (verification agent) = +1 opus agent, only when gaps detected. Saves opus cost in ~80% of cases.

## Standard Finding Format

All agents report findings in this format. The prefix uses the project shortname.

**LANGUAGE RULE:** ALL narrative text (Problema, Impacto, Correcao Sugerida, Como Testar) MUST be in Portugues de Portugal (PT-PT). Only inline technical references (file paths, method names, routes, SQL, config keys) stay in English within backticks.

**If an agent submits findings in English:**
- DA accepts but warns Maestro: "Aceitar mas avisar — conteudo em ingles, traduzir antes de criar ticket."
- Maestro attempts cosmetic PT-PT translation (no source code reading, just text translation)
- If Maestro lacks context -> sends finding BACK to original agent: "Reescreve em PT-PT. Termos tecnicos inline em ingles." -> agent re-submits -> normal DA path

**Formatting rule:** Use `inline code` (backticks) for ALL technical references.

```markdown
### SHORTNAME - Titulo curto em PT-PT
- **Severidade:** Critical / High / Medium / Low
- **Confianca:** 80-100%
- **Ficheiro:** `path/to/file.php:L45`
- **Rota:** `GET|POST /path/to/route` (when applicable)
- **Estimativa:** Xm

#### Problema
{2-3 frases em PT-PT com referencias `file.php:L45`.}

#### Impacto
{Consequencias concretas e especificas em PT-PT.}

#### Evidencia
{Code block com path + line range.}

#### Correcao Sugerida
- [ ] {Passo com `file:line` e codigo inline}
- [ ] {Passo}

#### Como Testar
- [ ] {Accao especifica}
- [ ] {Accao}
```

### Qualidade das Descricoes

**Problema — BOM vs MAU:**
- MAU: "Falta autenticacao no endpoint."
- BOM: "O endpoint `OrderFileController@download` em `OrderFileController.php:L45` serve ficheiros sem qualquer verificacao de autenticacao ou autorizacao. Qualquer pessoa com o UID do ficheiro pode descarregar prescricoes medicas via `GET /orders/file/{uid}`."

**Impacto — BOM vs MAU:**
- MAU: "Pode ser explorado por atacantes."
- BOM: "Permite que utilizadores nao autenticados descarreguem prescricoes medicas de pacientes — violacao RGPD directa."

### Guia de Estimativa

Each finding MUST include a realistic time estimate. Only output the total — no breakdown in the ticket.

**Calculation reference (for agents — NOT included in ticket output):**

| Fase | Tipico |
|------|--------|
| Issue & branch | 8-12 min |
| Claude fix | 2-8 min |
| Review | 2-5 min |
| Testes | 3-10 min |
| MR & cleanup | 8-12 min |

**Estimation rules:**
- **Minimum:** 20m (even trivial fixes have workflow overhead)
- **Single-file, clear fix:** 25-35m
- **Multi-file, moderate complexity:** 35-50m
- **Architectural change or multi-module:** 50-90m
- **Round to nearest 5 min**

## Maestro Checklist

1. **Phase 0 — Config Check:** Read MEMORY.md, check token, validate. **Check `.gitignore` for `.claude/code-reviews/`.**
2. **Phase 0B — Category Selection:** AskUserQuestion for categories
3. Read CLAUDE.md -> extract stack, conventions, security rules
4. Check git status -> current branch, recent changes
5. TeamCreate with descriptive name
6. Read each agent-prompt file from `agent-prompts/`
7. Spawn selected review agents (Agent tool, team_name)
8. Spawn devils-advocate with `MODE: FINDING-FILTER` (Agent tool, opus)
9. Create ClickUp main task: `CC Review YYYY-MM-DD` + ALL area subtasks upfront
10. **Create local folder tree:** Main folder + all area subfolders + `_main.md` + `_area.md` files (with YAML frontmatter)
11. **Keepalive:** Send periodic messages to DA during long processing (~2 min intervals)
12. **Liveness check:** Before declaring "all processed", ping DA and wait for response. If no response -> DA died -> check for orphaned findings (sent but no verdict) -> re-submit to new DA.
13. **GATE:** As DA streams APPROVED verdicts (NOT specialist findings) -> check idempotency (fuzzy match) -> create finding subtask (POST) -> **create local `.md` file** -> compose description locally -> PUT to ClickUp -> update frontmatter. NEVER create tickets from specialist messages directly.
14. Track rejected findings per area (title, verdict type, DA reason)
15. Track orphans: `{finding_id: sent_to_DA_at, verdict_received: bool}`. Any with `sent_to_DA_at > 5min ago` and no verdict -> orphan -> re-submit
16. When DA signals "all processed":
    a. Update area subtask descriptions + local `_area.md` with approved count + rejected table
    b. Update main task description + local `_main.md` with final statistics
17. **Security Verification:** If DA reported coverage gaps -> spawn verification agent
18. **Data-driven summary:** Query ClickUp for real tickets, build summary from query results
19. Present summary to user

## ClickUp API Reference

**All patterns are in `references/clickup-api-patterns.md`.** Key rules:

- **NEVER** pipe curl to jq (ClickUp control chars break JSON parsers)
- **ALWAYS** capture to variable, extract with grep
- **ALWAYS** use `markdown_description` field (not `description`)
- **ALWAYS** use `?include_markdown_description=true` on GET
- **Rate limiting:** Proactive counter at 80/min, sleep 20s. If 429: wait 60s, retry once.

### Severity -> Priority mapping

| Severity | ClickUp Priority | priority value |
|----------|-----------------|----------------|
| Critical | Urgent | 1 |
| High | High | 2 |
| Medium | Normal | 3 |
| Low | Low | 4 |

## ANTI-HALLUCINATION RULE — Summary Output

The summary is a REPORT of what exists in ClickUp, not a RECOLLECTION of what you think happened.

**MANDATORY procedure before generating summary:**

1. Query ClickUp: `GET /list/${LIST_ID}/task?subtasks=true&include_markdown_description=true`
2. Parse real tickets: extract name, priority, area (from parent), ticket ID
3. Build summary table EXCLUSIVELY from query results
4. Every finding in the summary MUST include its ClickUp ticket ID (e.g., `86c8p1e5e`)
5. If a finding is "in memory" but NOT in ClickUp -> it does NOT exist, do NOT include it
6. If you cannot query ClickUp -> state: "Resumo nao verificado — impossivel consultar ClickUp."

**Summary format:**

```markdown
## Code Review Summary — YYYY-MM-DD

Resumo gerado a partir de {N} tickets reais no ClickUp. Cada finding tem ticket ID verificavel.

| Area | Found | Approved | Rejected | Ticket IDs |
|------|-------|----------|----------|------------|
| Security | X | Y | Z | `id1`, `id2` |
| Performance | X | Y | Z | `id3` |
| Quality | X | Y | Z | `id4`, `id5` |
| Complexity | X | Y | Z | |
| Frontend | X | Y | Z | |
| QA | X | Y | Z | |
| **Total** | **X** | **Y** | **Z** | |

**ClickUp:** [Link to main task]

### Rejected Findings (for reference)
- [Finding title] — Verdict type — Reason
```

## Agent Governance

### Only the Maestro sends shutdown_request

No agent may autonomously decide to terminate another agent. Shutdown is exclusively a Maestro decision.

### Keepalive during long operations

During long operations (e.g., DA filtering 79 findings, security verification pass), Maestro sends periodic messages to active agents: "Still processing, continue." at ~2 minute intervals. This prevents Claude Code's idle timeout from killing agents mid-work.

### Liveness check before declaring completion

Before declaring any phase complete, Maestro pings active agents and waits for response. If no response:
1. Agent has died (idle timeout or context overflow)
2. Check for orphaned work (findings sent but no verdict received)
3. Re-submit orphaned items to a new agent instance
4. Log the incident

### Progress tracking

After each ticket action (create, skip, duplicate), append to `/tmp/clickup-audit-progress-{date}.log`:
```
{timestamp} | {ticket_id} | {action} | {area} | {title}
```
This file survives context compaction and enables session resumption.
