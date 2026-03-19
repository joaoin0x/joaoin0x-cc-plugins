# Investigation Protocol Reference

Technical reference for the planning skill. The Maestro and investigation agents use this document for API patterns, data formats, and error handling.

**API Patterns:** See `references/clickup-api-patterns.md` (at plugin root) for canonical token extraction, response handling, rate limiting, and error handling patterns. This file covers planning-specific patterns only.

## Planning Data Storage Format

Planning data is stored in the **task description** using `markdown_description` field. Audit sections are IMMUTABLE. Planning adds a structured `#### Planeamento` section at the bottom (before `#### Nome do Issue` if present). Refined versions of audit sections go as `#####` sub-sections WITHIN `#### Planeamento`.

**NO HTML comment delimiters.** ClickUp renders `<!-- -->` as visible text. All data uses standard markdown sections.

### Ticket Description (after planning)

```markdown
- **Severidade:** {may be updated by investigation}
- **Confiança:** {percentage}
- **Ficheiro:** `path/to/file.php:L45`
- **Rota:** `GET|POST /path/to/route`
- **Estimativa:** {updated estimate}

#### Problema
{IMMUTABLE — original audit text. NOT modified by planning.}

#### Impacto
{IMMUTABLE — original audit text.}

#### Evidência
{IMMUTABLE — original code block.}

#### Correcção Sugerida
*(ver versão actualizada em Planeamento abaixo)*  ← SÓ se ##### sub-secção existe abaixo
- [ ] {Original audit steps — IMMUTABLE}
- [ ] {Step 2}
- [ ] {Step 3}

#### Como Testar
*(ver versão actualizada em Planeamento abaixo)*  ← SÓ se ##### sub-secção existe abaixo
- [ ] {Original audit steps — IMMUTABLE}
- [ ] {Step 2}
- [ ] {Step 3}

---
#### Planeamento
- **Agente:** {specialist-name}
- **Abordagem:** {A/B} — {descrição breve}
- **Abordagem {B/A} (rejeitada):** {razão breve}
- **QA:** unit / e2e / both / none
- **Ficheiros:** `file1.php:L45`, `file2.php:L120`
- **Dependências:** `86c8j7739`, `86c8j5q28` (ou: Nenhuma)
- **Wave:** {N}
- **Estimativa:** {Xm}

##### Correcção Sugerida (Actualizado após Planeamento)
{Versão refinada — só se planning MODIFICA o conteúdo original}

##### Como Testar (Actualizado após Planeamento)
{Versão refinada — só se planning MODIFICA o conteúdo original}

#### Feedback Humano
{Adicionado pelo CU Manager SE existem comentários ClickUp — omitido se sem comentários}
- **[YYYY-MM-DD @author]:** "Comentário"
  - **Acção:** {resposta}

#### Decisões Planning
- **DA (PLANNING-REVIEW):** {VALID/INVALID/NEEDS-CHANGE} (round N) — "{reasoning}"
- **Investigation:** {VALID/INVALID/PARTIAL} — "{reasoning}"
- **Maestro:** {decisão final}

---
#### Nome do Issue
` ` `
{task_id} - {SHORTNAME} - {titulo}
` ` `
```

### Key rules

- **Audit sections are IMMUTABLE:** Original `#### Problema`, `#### Impacto`, `#### Correcção Sugerida`, `#### Como Testar` sections are NEVER modified. Refined versions go as `#####` sub-sections inside `#### Planeamento`
- **Specialist reads FULL description:** The fix specialist gets the entire ticket. When `#####` sub-sections exist in Planeamento, those have PRECEDENCE over the original audit sections
- **Maestro uses `#### Planeamento` for routing:** Agent type, wave assignment, QA strategy, dependencies
- **Grep-friendly metadata:** Each field in Planeamento is on its own line with `**bold key:**` prefix for easy extraction

## Description Read/Write (via Local Cache)

**v4.1.0: The local `.md` file in `code-reviews/` is the composition surface. No GET→modify→PUT cycle needed. No GUARD 1/GUARD 2 needed.**

### Read (from local cache)

Read the finding's local `.md` file from `code-reviews/{review_dir}/{area_dir}/{task_id}.md`. The file contains YAML frontmatter followed by the full ticket description.

```bash
FINDING_FILE="code-reviews/${REVIEW_DIR}/${AREA_DIR}/${TASK_ID}.md"

# Extract content after YAML frontmatter
DESC_CONTENT=$(awk '/^---$/{n++; next} n>=2' "$FINDING_FILE")
```

**Fallback (v4.0.1 compatibility):** If local file doesn't exist (audit ran before v4.1.0), fall back to GET from ClickUp and create the local file:

```bash
if [ ! -f "$FINDING_FILE" ]; then
  RESPONSE=$(curl -s -X GET -H "Authorization: ${CLICKUP_API_TOKEN}" \
    "https://api.clickup.com/api/v2/task/${TASK_ID}?include_markdown_description=true")

  CURRENT_DESC=$(echo "$RESPONSE" | tr -d '\000-\011\013-\037' | python3 -c "
  import sys, json
  data = json.loads(sys.stdin.read())
  print(data.get('markdown_description', '') or '')
  ")

  # Create local file with frontmatter
  cat > "$FINDING_FILE" <<EOF
---
task_id: ${TASK_ID}
area: ${AREA_NAME}
status: planning
last_synced: ""
last_comment_id: ""
---
${CURRENT_DESC}
EOF
fi
```

### Write (enrich locally, then PUT)

```bash
# After enriching the local file content:
DESC_CONTENT=$(awk '/^---$/{n++; next} n>=2' "$FINDING_FILE")

JSON_PAYLOAD=$(python3 -c "
import json, sys
desc = sys.stdin.read()
print(json.dumps({'markdown_description': desc}))
" <<< "$DESC_CONTENT")

curl -s -X PUT -H "Authorization: ${CLICKUP_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "$JSON_PAYLOAD" \
  "https://api.clickup.com/api/v2/task/${TASK_ID}"
```

**WHY this is safe:** The local file is the single composition surface. No GET round-trip. If PUT fails, content is preserved locally and can be retried. No guards needed because the source is a real file, not an API response.

### Comments endpoint

See `references/clickup-api-patterns.md` for the comment endpoint pattern. The Maestro fetches comments via `GET /task/{id}/comment` and compares against `last_comment_id` in frontmatter.

### Feedback Humano section

If new comments were found, the ClickUp Manager adds a `#### Feedback Humano` section to the description (content proposed by the specialist, written by CU Manager) (between `#### Como Testar` and `#### Planeamento`):

```markdown
#### Feedback Humano
- **[2026-03-09 @senior]:** "Isto e by-design, usamos policy em vez de middleware."
  - **Acção:** Investigado — policy tem bug no check de department. Novo ticket criado: `86c8jXXXX`
- **[2026-03-10 @senior]:** "Usar eager loading aqui."
  - **Acção:** Planeamento actualizado conforme instrução.
```

### Estimation update

Planning skill also updates `Estimativa` using the same rules from audit SKILL.md:
- **Minimum:** 20m
- **Single-file, clear fix:** 25-35m
- **Multi-file, moderate complexity:** 35-50m
- **Architectural:** 50-90m
- **Round to nearest 5 min**

## Status Case-Mapping Procedure

ClickUp status names are case-sensitive and space-sensitive. Every skill execution MUST build a case-mapping dictionary before making status updates.

### Step 1: Fetch actual status names

```bash
RESPONSE=$(curl -s -X GET -H "Authorization: ${CLICKUP_API_TOKEN}" \
  "https://api.clickup.com/api/v2/list/${LIST_ID}")
echo "$RESPONSE" | grep -o '"statuses":\[.*\]' | grep -o '"status":"[^"]*"'
```

### Step 2: Build mapping dictionary

Map lowercase canonical names to actual ClickUp names:
```
{
  "open": "Open",
  "planning": "planning",
  "ready for dev": "ready for dev",
  "in progress": "in progress",
  "testing": "testing",
  "deploy to staging": "deploy to staging",
  "closed": "Closed"
}
```

### Step 3: Handle missing statuses

If a required status is not found (even with case variations):
1. Present available statuses to the user via AskUserQuestion
2. Ask which existing status maps to the missing one
3. Store the mapping in MEMORY.md

### Step 4: Use mapped values in ALL status updates

```bash
STATUS_VALUE="planning"  # from mapping dict
curl -s -X PUT -H "Authorization: ${CLICKUP_API_TOKEN}" \
  -H "Content-Type: application/json" \
  -d "{\"status\":\"${STATUS_VALUE}\"}" \
  "https://api.clickup.com/api/v2/task/${TASK_ID}"
```

## Ticket Filtering by Area

When the user selects specific areas, filter tickets by matching the area subtask they belong to:

```
Main task (CC Review)
|-- Area subtask (Security)
|   |-- Finding ticket 1
|   '-- Finding ticket 2
|-- Area subtask (Performance)
|   '-- Finding ticket 3
...
```

Check each ticket's parent task name against the selected areas.

## Rate Limiting

**See `references/clickup-api-patterns.md` for the canonical counter pattern.**

- 80 requests/min: proactive sleep (20 seconds)
- 429 received: wait 60s, retry once

## Error Handling

| Scenario | Recovery |
|----------|----------|
| Ticket no longer exists | Skip, note in summary |
| Issue already fixed in codebase | Report INVALID, DA confirms, close with comment |
| Cannot access referenced files | Report BLOCKER, skip ticket |
| ClickUp API 429 | Wait 60s, retry once |
| Agent context overflow | Notify Maestro, request batch split (max 15 tickets) |
| Status name mismatch | Case-mapping from list API, ask user if no match |
| Planning run on already-planned | Fetch "open" + "planning", present separately |

## Immediate Status Updates (MANDATORY)

| Action completed | Update to |
|-----------------|-----------|
| Investigation starts for a ticket | `open` -> `planning` |
| Investigation validates ticket | Keep `planning` (description updated) |
| Investigation invalidates ticket | `planning` -> `Closed` (with comment) |
| DA confirms all assessments in batch | `planning` -> `ready for dev` |
| DA requests re-investigation | Keep `planning` (agent re-investigates) |

**NEVER batch status updates at the end.**
