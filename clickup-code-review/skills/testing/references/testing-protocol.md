# Testing Protocol Reference (v5.0)

Technical reference for the testing skill. The Maestro, QA Specialist, DA, and ClickUp Manager use this document for Chrome DevTools MCP methodology, login handling, screenshot rules, and QA verdict routing.

**v5.0: This is a NEW reference.** Browser testing was previously embedded in the fix skill. Now it's separated with its own protocol and methodology.

**API Patterns:** See `references/clickup-api-patterns.md` (at plugin root) for canonical ClickUp API interaction patterns.

**Key principle:** Chrome DevTools MCP is MANDATORY for all browser tests. If not available, do NOT proceed — report to Maestro immediately.

---

## Chrome DevTools MCP — Required Tools

### Core Tools (used in every test)

| Tool | Purpose | When |
|------|---------|------|
| `navigate_page` | Load a URL in the browser | Every page test |
| `wait_for` | Wait for element to appear | After navigation |
| `evaluate_script` | Run JS in page context | Title check, element visibility |
| `list_console_messages` | Capture JS errors | After page load |
| `list_network_requests` | Capture HTTP errors | After page load |
| `take_screenshot` | Visual evidence (temporary) | When needed for debugging |

### Interaction Tools (Level 2 — Functional tests)

| Tool | Purpose | When |
|------|---------|------|
| `click` | Click buttons, links, dropdowns | CRUD, filters, pagination |
| `fill` | Fill text inputs | Search, forms |
| `press_key` | Keyboard actions (Enter, Tab) | Search submit, navigation |
| `select_page` | Switch between browser tabs | Multi-tab workflows |
| `fill_form` | Fill multiple form fields at once | Complex forms |
| `hover` | Hover over elements | Tooltips, dropdown menus |
| `upload_file` | Upload files to input elements | File upload testing |

### Diagnostic Tools (used when investigating issues)

| Tool | Purpose | When |
|------|---------|------|
| `list_pages` | List open browser pages | Session management |
| `get_console_message` | Get specific console message details | Error investigation |
| `get_network_request` | Get specific request details | 4xx/5xx investigation |

---

## Login Protocol

### Credential Detection (automatic, ordered by priority)

```
1. .claude/credentials.local.md
   - PREFERRED source (follows CLAUDE.md policy)
   - Parse: look for test user table with email/password/role columns
   - Use admin/manager role for maximum access

2. .env
   - FALLBACK (APP_URL for base URL, credentials if documented)
   - Parse: APP_URL, TEST_EMAIL, TEST_PASSWORD (if present)

3. AskUserQuestion
   - LAST RESORT (only if both files don't exist or lack credentials)
   - Ask for: email, password, base URL
```

### Login Execution

```
STEP 1: Navigate to login page
  navigate_page(url="{APP_URL}/login")
  wait_for(selector="form", timeout=10000)

STEP 2: Fill credentials
  fill(selector="input[name='email']", value="{email}")
  fill(selector="input[name='password']", value="{password}")

STEP 3: Submit
  click(selector="button[type='submit']")
  OR press_key(key="Enter")

STEP 4: Verify login success
  wait_for(selector="body", timeout=10000)
  evaluate_script(expression="document.title")
  → If title contains "Login" or URL contains "/login": LOGIN FAILED
  → If redirected to dashboard/home: LOGIN SUCCESS

STEP 5: Log result
  Append to {REVIEW_DIR}/qa/qa-progress.md:
  "{timestamp} | LOGIN | {PASS/FAIL} | {url_after_login}"
```

### Session Expiry Recovery (automatic)

```
DETECTION:
  After EVERY navigate_page(), check:
  1. evaluate_script("window.location.href")
  2. If URL contains "/login" AND we were NOT navigating to login:
     → Session expired

RECOVERY:
  1. Log: "{timestamp} | SESSION_EXPIRED | re-login | {intended_url}"
  2. Execute Login Protocol (Steps 1-4)
  3. Re-navigate to intended URL
  4. Continue test from where it was interrupted

LIMIT: Max 3 re-logins per session. After 3rd:
  → Report to Maestro: "Session instavel — 3 re-logins. Possivel problema de auth."
```

### Multi-Role Testing (when required by ticket)

```
WHEN: Ticket requires testing with different roles (e.g., admin vs regular user)

PROTOCOL:
  1. Complete all tests for current role
  2. Navigate to logout URL (typically /logout)
  3. Log: "{timestamp} | ROLE_SWITCH | {from_role} -> {to_role}"
  4. Execute Login Protocol with new role's credentials
  5. Continue tests for new role

CREDENTIAL SOURCE: .claude/credentials.local.md (must have multiple role entries)
```

---

## Test Methodology — Level 1 (Smoke)

Applied to ALL pages. Goal: verify page loads without errors.

### Per-Page Procedure

```
STEP 1: NAVIGATE
  navigate_page(url="{page_url}")
  wait_for(selector="body", timeout=10000)

STEP 2: VERIFY NOT ERROR PAGE
  title = evaluate_script(expression="document.title")
  → If title contains "500", "404", "Error", "Exception": FAIL
  → If title is empty: WARN (some pages may have empty titles)

STEP 3: CHECK CONSOLE ERRORS
  messages = list_console_messages()
  Filter: IGNORE CSP warnings, IGNORE "DevTools" messages
  Filter: KEEP JS errors (TypeError, ReferenceError, SyntaxError, etc.)
  Filter: KEEP uncaught exceptions
  → If JS errors found: record as finding

STEP 4: CHECK NETWORK ERRORS
  requests = list_network_requests()
  Filter: KEEP 4xx responses (except 304 Not Modified)
  Filter: KEEP 5xx responses
  Filter: IGNORE successful requests (2xx, 3xx redirects)
  → If 4xx/5xx found: record as finding

STEP 5: VERIFY MAIN ELEMENT
  Detect page type and verify primary element:
  - Listing page: evaluate_script("document.querySelector('table, .datatable, .card-body')") != null
  - Form page: evaluate_script("document.querySelector('form')") != null
  - Dashboard: evaluate_script("document.querySelector('.card, .dashboard, .row')") != null
  → If no main element found: WARN (page may be empty or broken)

STEP 6: RECORD RESULT
  Append to {REVIEW_DIR}/qa/qa-progress.md:
  "{timestamp} | {url} | {PASS/FAIL} | {error_count} console, {error_count} network"
```

### Error Classification (Smoke)

| Error Type | Severity | Action |
|------------|----------|--------|
| 500 Server Error | Critical | Record finding immediately |
| 404 Not Found (page) | High | Record finding |
| 404 Not Found (asset) | Low | Record but don't fail page |
| JS TypeError/ReferenceError | Medium | Record finding |
| JS console.warn | — | Ignore |
| CSP violation warning | — | Ignore |
| Network timeout | High | Retry 1x, then record |

---

## Test Methodology — Level 2 (Functional)

Applied to pages with CRUD, forms, or interactive elements. EXTENDS Level 1 (all smoke checks run first).

**DEFINIÇÃO de Funcional:** Testar CADA elemento interactivo. "Navigate + check title" é smoke, NÃO funcional.

Ver `references/functional-checklists.md` para checklists por tipo de página (Listing, Form/Create, Edit, Show, Delete, Dashboard, Settings, Import/Export, Modal, State Transitions).

### Listing Page Tests

```
STEP 7A: VERIFY TABLE CONTENT
  evaluate_script("document.querySelectorAll('table tbody tr').length")
  → If 0 rows AND page should have data: WARN
  → If rows present: PASS

STEP 7B: TEST SEARCH (if search input exists)
  search_input = evaluate_script("document.querySelector('input[type=\"search\"], .dataTables_filter input, input[name=\"search\"]')")
  If exists:
    fill(selector="{search_selector}", value="test")
    press_key(key="Enter")
    wait_for(selector="body", timeout=5000)
    → Verify table updates (row count may change)
    → Clear search: fill(selector="{search_selector}", value="")
    → press_key(key="Enter")

STEP 7C: TEST PAGINATION (if pagination exists)
  pagination = evaluate_script("document.querySelector('.pagination, .dataTables_paginate')")
  If exists AND has next page:
    click(selector=".pagination .page-link[rel='next'], .paginate_button.next")
    wait_for(selector="body", timeout=5000)
    → Verify page changed (different rows or page indicator)

STEP 7D: TEST FILTERS (if filter dropdowns exist)
  filters = evaluate_script("document.querySelectorAll('select.form-select, select.form-control').length")
  If > 0:
    → Click first filter dropdown
    → Select second option (first non-default)
    → Verify table updates
    → Reset filter to default
```

### Form Page Tests

```
STEP 8A: IDENTIFY REQUIRED FIELDS
  required = evaluate_script("document.querySelectorAll('[required], .required').length")
  Log: "{N} required fields detected"

STEP 8B: FILL WITH TEST DATA
  For each required field:
    - Text input: fill with "Test {field_name} {timestamp}"
    - Email input: fill with "test@example.com"
    - Number input: fill with "1"
    - Select: select first non-empty option
    - Date: fill with today's date
    - Textarea: fill with "Test data for QA validation"

STEP 8C: SUBMIT
  click(selector="button[type='submit'], input[type='submit'], .btn-primary[type='submit']")
  wait_for(selector="body", timeout=10000)

STEP 8D: VERIFY RESULT
  → Check URL changed (redirect after success)
  → Check for flash/success message: evaluate_script("document.querySelector('.alert-success, .toast-success')")
  → Check for validation errors: evaluate_script("document.querySelector('.alert-danger, .invalid-feedback')")
  → If validation errors: record as WARN (may be expected if test data insufficient)
  → If success: PASS
```

### CRUD Cycle Tests

```
STEP 9A: CREATE
  Navigate to create page (click "New" or "Create" button)
  Fill required fields (Step 8B)
  Submit (Step 8C)
  Verify redirect to index or show page
  Record: "{timestamp} | CRUD | {entity} | CREATE | {PASS/FAIL}"

STEP 9B: SHOW (if show page exists)
  Click on created record in list
  Verify detail page loads with correct data
  Record: "{timestamp} | CRUD | {entity} | SHOW | {PASS/FAIL}"

STEP 9C: EDIT
  Navigate to edit page (click "Edit" button)
  Modify one field (append " (edited)" to text field)
  Submit
  Verify changes saved (redirect + flash message)
  Record: "{timestamp} | CRUD | {entity} | EDIT | {PASS/FAIL}"

STEP 9D: DELETE
  Click delete button
  Handle confirmation dialog:
    handle_dialog(accept=true)
    OR click confirm button in modal
  Verify record removed from list
  Record: "{timestamp} | CRUD | {entity} | DELETE | {PASS/FAIL}"

IMPORTANT: After CRUD cycle, verify list page still works (smoke check)
```

---

## Pre/Post-Navigation Log Analysis

### Purpose

Detect server-side errors that don't manifest in the browser (silent 500s, queue failures, background job errors).

### Protocol

```
PRE-NAVIGATION (once at start of testing session):
  1. Read storage/logs/laravel.log (last 50 lines)
  2. Record line count as BASELINE_LINE_COUNT
  3. Record last error timestamp as BASELINE_TIMESTAMP
  4. Store in {REVIEW_DIR}/qa/qa-log-baseline.md

POST-NAVIGATION (after each page or batch of pages):
  1. Read storage/logs/laravel.log (from BASELINE_LINE_COUNT onwards)
  2. Filter for new entries:
     - ERROR level → Critical (record finding)
     - WARNING level → Medium (record if relevant)
     - INFO/DEBUG → Ignore
  3. Correlate errors with tested pages:
     - Match timestamp with navigation timeline
     - Match URL/route in error message with tested page
  4. If new errors found:
     - Include in page test result
     - Add to finding if reporting to DA
  5. Update BASELINE_LINE_COUNT

EDGE CASES:
  - Log file doesn't exist → Skip log analysis, note in report
  - Log file rotated → Detect by checking file size/first line, reset baseline
  - Logs recently cleared → Start with empty baseline
```

---

## QA → DA SendMessage Templates

### Template: QA-REVIEW (ticket validation)

```markdown
## QA REVIEW — {Ticket Title}
**Ticket ID:** {clickup_task_id}

### Original Bug
**Problema:** {from ticket .md — Problema section}
**Correcção aplicada:** {from Fix Log / Commit section}
**Commit SHA:** `{sha}`

### Test Evidence
- **URLs testadas:** {list of all URLs visited}
- **Accoes executadas:** {specific actions: clicks, fills, navigations — NOT vague}
- **Bug original:** CORRIGIDO / PERSISTE
- **Console errors:** {list with details, or 'nenhum'}
- **Network errors:** {list with status codes, or 'nenhum'}
- **CRUD:** PASS / FAIL / N/A
- **Log errors (server-side):** {new errors found, or 'nenhum'}
- **Evidência adicional:** {description of anything notable}

### Test Depth
- **Level:** Smoke / Functional / CRUD Cycle
- **Pages tested:** {count}
- **Duration:** {time spent on this ticket's tests}
```

### Template: FINDING-FILTER (new bug discovery)

Uses the standard finding format from the audit skill:

```markdown
### {SHORTNAME} - {Titulo curto em PT-PT}
- **Severidade:** Critical / High / Medium / Low
- **Confiança:** {80-100}%
- **Ficheiro:** `{path/to/file.php}:{line}` (if identifiable from browser)
- **Rota:** `{METHOD /route/path}`
- **Estimativa:** {Xm}

#### Problema
{Descricao do bug encontrado em PT-PT. URL, accao, resultado.}

#### Impacto
{Consequencias concretas.}

#### Evidência
{Console errors, network errors, screenshots description, log entries.}

#### Correcção Sugerida
{Se possivel: hipotese de causa root e sugestao de fix.}

#### Como Testar
{Passos para reproduzir o bug — auto-suficientes.}
```

---

## Screenshot Management

### Rules (MANDATORY)

1. **Screenshots are WORKING TOOLS** — used for debugging, NOT deliverables
2. **Take screenshots** when investigating visual bugs or CRUD failures
3. **Reference screenshots** in QA evidence by description, NOT by file path
4. **NEVER include screenshots** in ClickUp tickets or .md files
5. **DELETE ALL screenshots** before QA Specialist shutdown

### Cleanup Protocol

```
BEFORE SHUTDOWN:
  1. List all screenshots taken during session
  2. Delete each screenshot file
  3. Verify deletion: no screenshot files remain
  4. Log: "{timestamp} | CLEANUP | {N} screenshots deleted"

IF QA SPECIALIST DIES MID-SESSION:
  Maestro checks {REVIEW_DIR}/qa/ for orphaned screenshots
  Maestro deletes orphaned screenshots before re-spawning QA Specialist
```

---

## Progress Tracking

### Per-Page Progress File

**File:** `{REVIEW_DIR}/qa/qa-progress.md`

**Format (append after EACH page):**
```
{ISO_timestamp} | {url} | {PASS/FAIL} | console:{N} network:{N} | {notes}
```

**Examples:**
```
2026-03-10T14:05:00Z | /manager/dashboard | PASS | console:0 network:0 |
2026-03-10T14:05:30Z | /manager/users | PASS | console:0 network:0 |
2026-03-10T14:06:00Z | /manager/ponto/import | FAIL | console:1 network:0 | TypeError in import.js
2026-03-10T14:06:30Z | /manager/hr/shifts | FAIL | console:0 network:1 | 500 on /api/shifts
```

### Per-Ticket Progress (for "tickets" mode)

**File:** `{REVIEW_DIR}/qa/testing-progress-{date}.log`

**Format (append after EACH ticket action):**
```
{ISO_timestamp} | {ticket_id} | {action} | {result}
```

**Examples:**
```
2026-03-10T14:10:00Z | 86c8qhcfx | NAVIGATE | /manager/ponto/import
2026-03-10T14:10:15Z | 86c8qhcfx | REPRODUCE | bug no longer exists
2026-03-10T14:10:30Z | 86c8qhcfx | CONSOLE_CHECK | 0 errors
2026-03-10T14:10:45Z | 86c8qhcfx | NETWORK_CHECK | 0 errors
2026-03-10T14:11:00Z | 86c8qhcfx | SENT_TO_DA | QA-REVIEW evidence
2026-03-10T14:12:00Z | 86c8qhcfx | DA_VERDICT | QA-APPROVED
```

---

## Test Suite Baseline (PHPUnit/Pest)

### Protocol

```
STEP 1: RUN TEST SUITE
  Execute: sail artisan test (or project equivalent)
  Capture: total, passed, failed, skipped counts

STEP 2: COMPARE WITH PREVIOUS BASELINE
  Read {REVIEW_DIR}/qa/test-suite-{previous_date}.md (if exists)
  Compare:
  - NEW failures (not in previous baseline): CRITICAL — report to Maestro immediately
  - Pre-existing failures (same as baseline): NOTE but do NOT block
  - Previously failing now passing: POSITIVE — note improvement

STEP 3: RECORD BASELINE
  Write to {REVIEW_DIR}/qa/test-suite-{date}.md:
  ```
  ## Test Suite Baseline — {date}
  - **Total:** {N}
  - **Passed:** {X}
  - **Failed:** {Y} (pre-existing: {Y1}, new: {Y2})
  - **Skipped:** {Z}
  - **Compared with:** {previous_date or 'first run'}
  ```

STEP 4: REPORT
  Include baseline in testing summary
  If new failures detected: Maestro must investigate before proceeding
```

---

## Page Mapping Strategy

### Route-Based Mapping

```
STEP 1: READ ROUTE FILES
  Read routes/web.php + any included route files (hr.php, webmail.php, etc.)
  Extract: method, URI, controller, middleware

STEP 2: FILTER TESTABLE ROUTES
  Include: GET routes with 'auth' middleware (authenticated pages)
  Exclude: POST/PUT/DELETE routes (tested via CRUD cycles)
  Exclude: API routes (tested separately if needed)
  Exclude: Redirect-only routes

STEP 3: ORGANIZE BY MODULE
  Group routes by prefix/controller namespace:
  - /manager/dashboard → Dashboard
  - /manager/users/* → Users
  - /manager/hr/* → HR
  - /manager/webmail/* → Webmail
  - etc.

STEP 4: PRIORITIZE
  Priority 1: Pages of tickets at "testing" status (if any)
  Priority 2: Pages with CRUD (most likely to have bugs)
  Priority 3: Dashboard pages (high visibility)
  Priority 4: Settings/config pages (lower risk)

STEP 5: HANDLE PARAMETERIZED ROUTES
  Routes with {id} or {slug} parameters:
  - Navigate to listing page first
  - Extract first record's ID/link from the table
  - Use that ID for show/edit routes
  - If no records exist: skip with WARN
```

---

## Error Handling

| Scenario | Recovery |
|----------|----------|
| Chrome DevTools MCP not available | Report to Maestro, do NOT proceed with browser tests |
| Login fails | Try alternative credentials, then AskUserQuestion |
| Session expires mid-test | Auto re-login (max 3 times per session) |
| Page timeout (>10s) | Record as FAIL, continue to next page |
| navigate_page fails | Retry 1x, then record as FAIL |
| Console filled with CSP warnings | Filter out, focus on real JS errors |
| 429 Too Many Requests from app | Wait 10s, retry 1x |
| DA rejects QA evidence | QA Specialist re-tests 1x (max 1 round). After 2nd rejection → Maestro decides |
| Test data causes side effects | Use clearly marked test data ("QA Test {timestamp}") |
| CRUD delete fails (FK constraint) | Record as finding, do not force delete |
| Page requires specific data state | Check if data exists first, skip CRUD if insufficient data |

---

## Credential Security Rule

**MANDATORY for ALL QA Specialist output:**

- NEVER include real credentials in reports, findings, or evidence
- ALWAYS use placeholders: `{TEST_EMAIL}`, `{TEST_PASSWORD}`, `{APP_URL}`
- NEVER include credentials in SendMessage to DA
- NEVER include credentials in progress files ({REVIEW_DIR}/progress/)
- If credential appears in console/network output: redact before recording

**Example:**
```
# WRONG
Login: testes@farmaciaslourenco.pt / testes@farmaciaslourenco.pt

# CORRECT
Login: {TEST_EMAIL} / {TEST_PASSWORD} (from credentials.local.md)
```

---

## Verificação por Tipo de Ticket (v5.2.1)

### Verificação COMPLETA via browser (QA testa tudo funcionalmente)

- Frontend bugs, CRUD bugs, navigation, form validation, UI/UX
- Auth middleware → verificar 403/401 sem login
- IDOR → verificar acesso negado para outro user
- N+1 queries → verificar load time aceitável

### Requer COMPLEMENTO de code review (browser + DA review)

- SQL injection fix → browser testa input, DA revê sanitização no código
- Mass assignment → browser testa form, DA revê `$fillable`/`$guarded`
- CSRF token handling → browser testa form submission, DA revê middleware
- Session config → browser testa login/logout flow, DA revê config
- **Qualquer ticket de security/performance** → QA testa no browser + DA faz code review

### Protocolo (security/performance tickets)

1. QA Specialist testa TUDO via browser (funcional completo)
2. Para tickets security/performance: QA envia evidência ao DA
3. DA faz QA-REVIEW (browser evidence) + CODE-REVIEW (source code)
4. Verdict combina ambas as verificações
5. Sem caveat — ou está verificado completamente ou não está
