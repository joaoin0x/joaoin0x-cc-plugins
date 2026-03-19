# ClickUp Code Review Plugin (v5.2.4)

Multi-agent code review lifecycle for Claude Code: audit, planning, fixing, and functional testing, with ClickUp integration, evidence-based status gates, and a self-contained HTML dashboard.

## Pipeline

```
/clickup-code-review:setup     ->  Configuration (token, workspace, permissions)
/clickup-code-review:audit     ->  Audit (creates tickets at "open")
/clickup-code-review:planning  ->  Triage (open -> planning -> ready for dev)
/clickup-code-review:fix       ->  Execute (ready for dev -> ... -> testing)
/clickup-code-review:testing   ->  Validate (testing -> deploy to staging)
```

**Sequence:** setup -> audit -> planning -> fix -> testing. Each skill depends on the previous.

## Architecture

### 5 Skills

| Skill | Purpose |
|-------|---------|
| `:setup` | Interactive wizard: token, workspace, list, shortname, permissions, hook |
| `:audit` | 6 specialist agents analyse codebase in parallel, DA filters findings, ClickUp Manager creates tickets |
| `:planning` | Decentralised planning: each specialist plans their area, Investigation + DA validate, wave organisation |
| `:fix` | Serial queue execution with evidence gates, DA code review, commit SHA binding |
| `:testing` | Functional browser testing via Chrome DevTools MCP, QA fail severity routing |

### 9 Agents (all internalised in plugin)

| Agent | Model | Colour | Role |
|-------|-------|--------|------|
| `security-specialist` | opus | magenta | OWASP, auth, IDOR, injection |
| `backend-specialist` | sonnet | blue | N+1, caching, queries, API |
| `frontend-specialist` | sonnet | green | WCAG 2.1, Bootstrap, Blade, Alpine.js |
| `quality-specialist` | sonnet | yellow | PSR-12, SOLID, casts, types |
| `qa-specialist` | sonnet | cyan | PHPUnit/Pest + browser testing (Chrome DevTools MCP) |
| `investigation-specialist` | opus | cyan | Cross-area dependencies, wave planning |
| `clickup-manager` | sonnet | blue | ALL ClickUp API operations + evidence gates |
| `devils-advocate` | opus | red | Sceptical gatekeeper (4 modes: FINDING-FILTER, PLANNING-REVIEW, CODE-REVIEW, QA-REVIEW) |
| `code-simplifier` | sonnet | yellow | Anti-complexity (audit + fix review) |

**Zero dependency on built-in Anthropic agent types.** All agents are plugin `.md` files with full expertise preambles.

### Separation of Responsibilities

```
MAESTRO (the user's Claude Code session)
  - Orchestrates workflow, spawns/resumes agents
  - Commits code (ONLY entity that commits)
  - Communicates with user
  - NEVER implements fixes, NEVER touches ClickUp API

CLICKUP MANAGER
  - ALL ClickUp API operations (create, update, status, comments)
  - Evidence gate verification
  - Local cache management (.claude/code-reviews/)
  - REFUSES status transitions without proof

SPECIALISTS (5 agents)
  - Analyse code (audit), plan fixes (planning), implement fixes (fix)
  - Report to DA (never to Maestro directly for review)

INVESTIGATION SPECIALIST
  - Cross-area dependency detection
  - Wave planning and conflict resolution
  - Ping-pong with DA for wave plan validation

DEVIL'S ADVOCATE
  - Validates ALL findings, plans, code, and test results
  - 4 modes with strict verdict protocols
  - Sole gate between specialists and Maestro

QA SPECIALIST
  - Fix skill: runs test suite (PHPUnit/Pest) after each wave
  - Testing skill: browser testing via Chrome DevTools MCP
```

## v5.0 Key Features

### Evidence Gates

Every status transition requires proof. The ClickUp Manager REFUSES transitions without evidence:

| Transition | Evidence Required |
|------------|-------------------|
| ready for dev -> in progress | `.md` local exists (MINIMUM), `#### Planeamento` present (IDEAL) |
| in progress -> code review | Staged diff exists + sent to DA via SendMessage |
| code review -> testing | DA APPROVED + Commit SHA verified + `#### Decisões Fix` documented |
| testing -> deploy to staging | DA QA-APPROVED verdict |
| testing -> ready for dev | DA QA-REJECTED (MINOR) |
| testing -> planning | DA QA-REJECTED (MODERATE/CRITICAL) |

### "code review" Intermediate Status

New status between "in progress" and "testing" that provides board visibility for which tickets are being implemented vs awaiting DA review.

### Read-Ahead Queue (v5.2.4)

PREPARE paralelo (max 3, read-only, persiste `.prepare.md`) → IMPLEMENT serial (write/stage). Staleness check, deadlock detection, fallback to serial. Wave grouping mantém-se para ordenação/dependências.

### Decentralised Planning

Each specialist plans their own area's tickets (in parallel). Investigation + DA do meta-organisation (waves, dependencies, conflicts). Triangle validation: Specialist + DA + Investigation must all agree.

### Ticket Consolidation (Merge)

Investigation can propose merging same-area tickets that share files (criteria: same area, Medium/Low severity, compatible QA, non-conflicting fixes, combined scope <= 5 files).

### QA Fail Severity Routing

| Severity | Routing |
|----------|---------|
| MINOR (cosmetic) | testing -> ready for dev (quick-fix next `/fix` run) |
| MODERATE (partially broken) | testing -> planning (re-investigate) |
| CRITICAL (completely broken) | testing -> planning + Maestro alert |

Cascade blocking via native ClickUp dependencies API when ticket A fails and B, C, D depend on it.

### Dashboard

Self-contained HTML template (`templates/dashboard.html`) with `{{DASHBOARD_JSON}}` placeholder:
- 5 tabs: Setup, Audit, Planning, Fix, Testing
- Dark theme, Bootstrap 5.3 + Chart.js 4.x
- Client-side filters, sortable tables
- Export: Copy Markdown + Download CSV
- Pipeline Quality metrics (false positive rate, severity drift, rejection correlation)

Each skill ADDS to the JSON cumulatively. Maestro writes output to `.claude/code-reviews/{dir}/dashboard.html`.

### 3-Layer Resilience

```
{REVIEW_DIR}/progress/agent-{name}-progress.md   (project-scoped)
    |
    v  Maestro reads
.claude/code-reviews/{dir}/      (permanent SOT, YAML frontmatter + markdown body)
    |
    v  ClickUp Manager syncs
ClickUp API (task description)   (cloud, visible to team)
```

### Local File Cache

`.claude/code-reviews/` stores one `.md` per ticket with YAML frontmatter (task_id, area, severity, status, commit_sha, branch, last_synced, last_comment_id) and progressive body sections added by each skill phase.

### Credential Security

All agents enforce: NEVER include real credentials in ticket descriptions, comments, or evidence. Use placeholders (`{API_KEY}`, `{DB_PASSWORD}`). ClickUp Manager scans for credential patterns before every PUT.

## Status Flow

```
open -> planning -> ready for dev -> in progress -> code review -> testing -> deploy to staging
                                          ^                |              |
                                          |    (DA REQUEST-CHANGES)       |
                                          +------- in progress <---------+
                                                                    (QA-REJECTED MINOR -> ready for dev)
                                                                    (QA-REJECTED MOD/CRIT -> planning)
```

## Installation

### 1. Register the local marketplace (once)

```
/plugin marketplace add ~/.claude-personal/my-plugins
```

### 2. Install the plugin

```
/plugin install clickup-code-review@local-plugins
```

### 3. Verify

```
/skills
```

Should show 5 skills: `clickup-code-review:audit`, `:planning`, `:fix`, `:testing`, `:setup`.

## Configuration

### Automatic (recommended)

```
/clickup-code-review:setup
```

The wizard configures:
1. **Installation detection** — CLDP (`~/.claude-personal/`) vs CLDW (`~/.claude/`)
2. **API Token** — Stored in `settings.json` -> `env.CLICKUP_API_TOKEN`
3. **Workspace/List** — Interactive hierarchy navigation
4. **Shortname** — Project slug for ticket titles (e.g., FSL)
5. **Permissions** — Pre-authorised ClickUp API + dependency + evidence gate operations
6. **Hook** — PreToolUse hook for multi-statement script auto-approval

### Manual

**Token in settings.json:**
```json
{ "env": { "CLICKUP_API_TOKEN": "pk_..." } }
```

**Project in MEMORY.md:**
```markdown
## ClickUp
- **List ID:** 901520510817
- **Shortname:** FSL
```

## Plugin Structure

```
clickup-code-review/
├── .claude-plugin/
│   └── plugin.json
├── agents/                          # 9 internalised agents (v5.0)
│   ├── security-specialist.md       # opus — OWASP, auth, injection
│   ├── backend-specialist.md        # sonnet — N+1, caching, queries
│   ├── frontend-specialist.md       # sonnet — WCAG, Bootstrap, Blade
│   ├── quality-specialist.md        # sonnet — PSR-12, SOLID, casts
│   ├── qa-specialist.md             # sonnet — PHPUnit + Chrome DevTools
│   ├── investigation-specialist.md  # opus — cross-area, wave planning
│   ├── clickup-manager.md           # sonnet — ClickUp API + evidence gates
│   ├── devils-advocate.md           # opus — sceptical gatekeeper (4 modes)
│   └── code-simplifier.md           # sonnet — anti-complexity
├── hooks/
│   ├── hooks.json                   # Plugin-bundled PreToolUse matchers (v5.2.4)
│   ├── orchestration-auto-approve.sh  # Agent/SendMessage auto-approve
│   ├── file-ops-auto-approve.sh     # Write/Edit/Read auto-approve (deny .env/.sh; whitelist safe exts)
│   ├── bash-safe-auto-approve.sh    # Bash auto-approve: git read-only, staging, commits, test runners
│   └── clickup-auto-approve.sh      # Setup wizard template (installed to user hooks dir)
├── references/
│   └── clickup-api-patterns.md      # Shared API patterns (all skills)
├── skills/
│   ├── shared/                      # Shared protocols (v5.2.4 — referenced by all agents)
│   │   ├── pipeline-rules.md        # Communication, streaming, progress, credentials, forbidden
│   │   ├── planning-protocol.md     # PASSO skeleton, triangle validation, planeamento template
│   │   └── fix-protocol.md          # PASSO skeleton, specialist↔DA flow, evidence gates
│   ├── audit/                       # Skill: Audit
│   │   └── SKILL.md
│   ├── planning/                    # Skill: Planning
│   │   ├── SKILL.md
│   │   └── references/
│   ├── fix/                         # Skill: Fix
│   │   ├── SKILL.md
│   │   └── references/
│   │       └── fix-protocol.md
│   ├── testing/                     # Skill: Testing
│   │   ├── SKILL.md
│   │   └── references/
│   │       └── testing-protocol.md
│   └── setup/                       # Skill: Setup wizard
│       └── SKILL.md
├── templates/
│   └── dashboard.html               # Dashboard template
├── docs/
│   ├── v5.0-architecture-plan.md    # Architecture SOT
│   ├── v5.0.1-plan-archive.md       # Archived v5.0.1 items
│   ├── v5.0.1-post-test-fixes-design.md  # Post-test fix design
│   ├── v5.0.2-agent-restructuring-plan.md  # v5.0.2 restructuring plan
│   └── v4-archive/                  # Archived v4 prompts (read-only)
└── README.md
```

## Agent Modes per Skill

| Agent | Audit | Planning | Fix | Testing |
|-------|-------|----------|-----|---------|
| Security Specialist | Analyse | Plan fixes | Implement | — |
| Backend Specialist | Analyse | Plan fixes | Implement | — |
| Frontend Specialist | Analyse | Plan fixes | Implement | — |
| Quality Specialist | Analyse | Plan fixes | Implement | — |
| QA Specialist | Unit+E2E audit | — | Test suite after wave | Browser testing |
| Investigation | — | Meta-org (waves+deps) | — | — |
| ClickUp Manager | Create tickets | Update tickets | Evidence gates | QA fail flow |
| Devil's Advocate | FINDING-FILTER | PLANNING-REVIEW | CODE-REVIEW | QA-REVIEW |
| Code Simplifier | Complexity audit | — | Review diffs | — |

## Communication Rules

- Any agent can talk to any other via SendMessage (collaboration encouraged)
- Maestro receives copies of ALL critical messages (verdicts, escalations, blockers)
- ONLY Maestro talks to the user
- ONLY ClickUp Manager touches the ClickUp API

## API Patterns

See `references/clickup-api-patterns.md` for:
- Token extraction (Python, not grep)
- Status case-mapping (mandatory GET /list/{id} first)
- Rate limiting (proactive 80/min, 429: wait 60s)
- Never pipe curl to jq (ClickUp control characters)
- Always use `markdown_description` field (never `description`)
- Never GET description to modify — compose locally and PUT

## Architecture SOT

The complete v5.0 architecture specification lives at `docs/v5.0-architecture-plan.md`. All design decisions, agent procedures, evidence gate protocols, and workflow details are documented there.
