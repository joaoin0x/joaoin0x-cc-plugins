---
name: clickup-code-review:setup
description: Interactive setup wizard for the ClickUp Code Review plugin. Configures API token, workspace, list, shortname, pre-authorized permissions, auto-approve hook, and local cache gitignore. Use when the user asks to "configure ClickUp", "set up the code review plugin", "reconfigure ClickUp permissions", or when running the plugin for the first time.
user_invocable: true
---

# ClickUp Code Review — Setup Wizard

Interactive configuration for the ClickUp Code Review plugin. Guides the user through token setup, workspace navigation, and permission pre-authorization.

**API Patterns:** See `references/clickup-api-patterns.md` (at plugin root) for canonical token extraction, response handling, and error handling patterns.

## When to Use

- First time running the plugin (auto-triggered by Phase 0)
- Reconfiguring the plugin (`/clickup-code-review:setup`)
- Changing workspace, list, or shortname for a project
- Adding or modifying pre-authorized permissions

## Step 1: Detect settings.json

Find the user's Claude Code settings file. Check in order:

1. `$PWD/.claude/settings.json` — project-level settings
2. `$HOME/.claude-personal/settings.json` — CLDP (Personal installation)
3. `$HOME/.claude/settings.json` — CLDW (Professional/standard installation)

**Detection logic:**
- Read each file and check if `enabledPlugins` contains a key matching `clickup-code-review`
- Use the FIRST match found
- Present the detected installation to the user for confirmation:

```
AskUserQuestion: "Detectei a instalação Claude Code em: {SETTINGS_PATH}"
  Installation type: {CLDP (Personal) / CLDW (Professional) / Project-level}
Options:
- "Confirmar — usar {SETTINGS_PATH}" (Recommended)
- "$HOME/.claude-personal/settings.json" (CLDP Personal)
- "$HOME/.claude/settings.json" (CLDW Professional)
- "Outro caminho" (let user type)
```

- If no match found in any of the 3 paths, ask directly (show all 3 options + "Outro caminho")

Store the detected path as `SETTINGS_PATH` for subsequent steps.

**IMPORTANT:** Use `$HOME` (not hardcoded paths) for cross-OS compatibility (macOS, Linux, Windows WSL).

## Step 2: API Token

### 2.1 Check existing token

Check in order:
1. Environment variable `$CLICKUP_API_TOKEN` (may already be set via settings.json `env`)
2. Read `SETTINGS_PATH` using the canonical Python extraction pattern from `references/clickup-api-patterns.md`

If found, show to user and confirm:

```
AskUserQuestion: "Token ClickUp existente: pk_****{last4}. Manter ou alterar?"
Options:
- "Manter token actual" (Recommended)
- "Alterar token"
```

If user keeps, skip to validation (2.3). If "Alterar", proceed to 2.2.

### 2.2 Ask for token

```
AskUserQuestion: "Preciso do teu API Token do ClickUp (começa com pk_). Podes gerar um em https://app.clickup.com/settings/apps"
Options:
- "Já tenho o token" (user pastes it)
- "Preciso de ajuda para gerar" (show instructions)
```

If user needs help:
> 1. Abre https://app.clickup.com/settings/apps
> 2. Clica em "Generate" na secção "API Token"
> 3. Copia o token (começa com `pk_`)

### 2.3 Validate token

1. Check format: must start with `pk_`
2. Test API call — see `references/clickup-api-patterns.md` for response handling rules:

```bash
RESPONSE=$(curl -s -X GET -H "Authorization: $TOKEN_VALUE" "https://api.clickup.com/api/v2/team")
# Extract team name with grep (NOT jq — ClickUp responses contain control chars)
TEAM_NAME=$(echo "$RESPONSE" | grep -o '"name":"[^"]*"' | head -1 | cut -d'"' -f4)
```

3. If `TEAM_NAME` is non-empty: token is valid, proceed
4. If empty or response contains `"err"`: inform user, ask to re-enter

### 2.4 Save token

Read the current `SETTINGS_PATH` file, then update the `env` section:

```json
{
  "env": {
    "CLICKUP_API_TOKEN": "pk_..."
  }
}
```

**IMPORTANT:** Merge into existing `env` — do NOT overwrite other env variables.

Use the Edit tool to add/update the `CLICKUP_API_TOKEN` key in the `env` object.

## Step 3: Workspace → Space → Folder → List

Navigate the ClickUp hierarchy interactively to find the target list for ticket creation.

### 3.1 Check existing config (ALWAYS confirm)

Read the project's MEMORY.md. Look for:
- `Workspace ID:` value
- `List ID:` value

**ALWAYS show current values and confirm, even if both exist.** The user may want different config per project.

```
AskUserQuestion: "Configuração ClickUp actual:"
  - Workspace ID: {id or "Não configurado"}
  - List ID: {id or "Não configurado"}
"Verificar e confirmar:"
Options:
- "Manter configuração actual" (Recommended) — only if both exist
- "Alterar workspace/list"
- "Configuração diferente para este projecto" — use project-level MEMORY.md override
```

If user keeps, skip to Step 4. If "Configuração diferente", create/update project MEMORY.md with separate ClickUp section.

### 3.2 Select Workspace

**IMPORTANT:** NEVER pipe curl to jq — ClickUp responses contain control characters that break JSON parsers. Always capture to variable first, then extract with grep.

```bash
RESPONSE=$(curl -s -X GET -H "Authorization: $CLICKUP_API_TOKEN" "https://api.clickup.com/api/v2/team")
# Extract workspace names and IDs with grep
echo "$RESPONSE" | grep -o '"id":"[^"]*"\|"name":"[^"]*"'
```

Present results via AskUserQuestion:
```
"Qual workspace queres usar?"
Options: [list workspace names, max 4 per page]
```

Store selected `workspace_id`.

### 3.3 Select Space

```bash
RESPONSE=$(curl -s -X GET -H "Authorization: $CLICKUP_API_TOKEN" "https://api.clickup.com/api/v2/team/{workspace_id}/space?archived=false")
echo "$RESPONSE" | grep -o '"id":"[^"]*"\|"name":"[^"]*"'
```

Present via AskUserQuestion. Store selected `space_id`.

### 3.4 Select Folder

```bash
RESPONSE=$(curl -s -X GET -H "Authorization: $CLICKUP_API_TOKEN" "https://api.clickup.com/api/v2/space/{space_id}/folder?archived=false")
echo "$RESPONSE" | grep -o '"id":"[^"]*"\|"name":"[^"]*"'
```

Present via AskUserQuestion. Include option "Sem folder (lists directamente no space)" for folderless lists.

If no folder selected, get lists directly from space:
```bash
RESPONSE=$(curl -s -X GET -H "Authorization: $CLICKUP_API_TOKEN" "https://api.clickup.com/api/v2/space/{space_id}/list?archived=false")
echo "$RESPONSE" | grep -o '"id":"[^"]*"\|"name":"[^"]*"'
```

### 3.5 Select List

If folder was selected:
```bash
RESPONSE=$(curl -s -X GET -H "Authorization: $CLICKUP_API_TOKEN" "https://api.clickup.com/api/v2/folder/{folder_id}/list?archived=false")
echo "$RESPONSE" | grep -o '"id":"[^"]*"\|"name":"[^"]*"'
```

Present via AskUserQuestion. Store selected `list_id`.

### 3.6 Save to MEMORY.md

Update the project's MEMORY.md with a `## ClickUp` section:

```markdown
## ClickUp
- **Workspace ID:** {workspace_id}
- **List ID:** {list_id}
```

If a ClickUp section already exists, update it. If not, append it.

## Step 4: Shortname

### 4.1 Check existing

Read MEMORY.md for `Shortname:` value.

If exists:
```
AskUserQuestion: "Shortname actual: {value}. Manter ou alterar?"
Options:
- "Manter '{value}'" (Recommended)
- "Alterar shortname"
```

### 4.2 Ask for shortname

```
AskUserQuestion: "Qual a slug do projecto para o título dos tickets? (ex: FSL, HT2, CDM)"
Options:
- (Let user type via "Other")
```

Note: Since all options would be examples, present it as a text input by providing example options the user will likely override.

### 4.3 Save to MEMORY.md

Add to the ClickUp section:
```markdown
- **Shortname:** {value}
```

## Step 5: Permission Pre-Authorization

Configure which ClickUp API operations are pre-authorized (no permission prompt during execution).

### 5.0 Check existing permissions (ALWAYS present)

Read `SETTINGS_PATH` and extract all ClickUp-related entries from `permissions.allow` (entries containing `api.clickup.com`). Count them against the 18 total possible.

**Build a lookup set** of currently authorized permission patterns for use in 5.1/5.2.

**ALWAYS present current permissions to the user, regardless of count.** The user may want different permissions per project or for reconfiguration.

```
AskUserQuestion: "{count}/18 permissões ClickUp configuradas. O que queres fazer?"
  Current: {list active permission names, e.g. "GET team, POST list/*/task, PUT task/*"}
Options:
- "Manter actuais" (Recommended) — Skip to Step 6 (only if count > 0)
- "Reconfigurar permissões" — Review all, can add or remove
- "Configuração diferente para este projecto"
```

If "Manter actuais" → skip to Step 6.
If "Reconfigurar" or "Configuração diferente" → proceed to Page 1.
If count == 0 → proceed to Page 1 directly (first-time setup).

### 5.1 Page 1 — Core Operations (4 questions, 15 operations)

**IMPORTANT — Active state indicators:**
Before presenting questions, check the lookup set from 5.0. For each option, append to the description:
- `✅ Activa` — if the corresponding permission pattern exists in `permissions.allow`
- (nothing) — if not currently authorized

This tells the user which permissions are already active, so they know what they're keeping or removing.

Use a SINGLE AskUserQuestion call with 4 questions:

```
AskUserQuestion (4 questions, all multiSelect):

Q1 header="Setup" question="Setup e Navegação — operações para navegar a hierarquia do ClickUp:"
Options:
- "Listar workspaces (GET /team)" — Necessária para setup [✅ Activa if exists]
- "Listar spaces (GET /team/*/space*)" — Necessária para setup [✅ Activa if exists]
- "Listar folders (GET /space/*)" — Necessária para setup [✅ Activa if exists]
- "Listar lists (GET /folder/*)" — Necessária para setup [✅ Activa if exists]

Q2 header="Review" question="Code Review — operações essenciais para o code review:"
Options:
- "Ver tasks numa list (GET /list/*)" — Necessária para review [✅ Activa if exists]
- "Ver task e comentários (GET /task/*)" — Útil para review [✅ Activa if exists]
- "Criar ticket (POST /list/*/task)" — Essencial para criar tickets [✅ Activa if exists]
- "Actualizar ticket (PUT /task/*)" — Essencial para stats finais [✅ Activa if exists]

Q3 header="Tasks" question="Acções em Tasks — operações adicionais sobre tasks:"
Options:
- "Comentários/anexos/tags (POST /task/*)" — Útil para detalhes [✅ Activa if exists]
- "Dependências (POST /task/*/dependency)" — Essencial v5.0: bloqueio em cascata QA [✅ Activa if exists]
- "Remover dependência (DELETE /task/*/dependency)" — Essencial v5.0: desbloquear após QA [✅ Activa if exists]
- "Remover tag (DELETE /task/*)" — Única operação de delete [✅ Activa if exists]
- "Timer/time entries (POST /team/*)" — Registar tempo [✅ Activa if exists]

Q4 header="Workspace" question="Gestão Workspace — criar e modificar estrutura:"
Options:
- "Criar folder (POST /space/*)" — Opcional [✅ Activa if exists]
- "Actualizar folder (PUT /folder/*)" — Opcional [✅ Activa if exists]
- "Criar list (POST /folder/*)" — Opcional [✅ Activa if exists]
- "Actualizar list (PUT /list/*)" — Opcional [✅ Activa if exists]
```

### 5.2 Page 2 — API v3 (1 question, 3 operations)

```
AskUserQuestion (multiSelect):

header="API v3" question="ClickUp API v3 — documentos e chat:"
Options:
- "Ler documentos/chat (GET /workspaces/*)" — Opcional [✅ Activa if exists]
- "Criar documento (POST /workspaces/*)" — Opcional [✅ Activa if exists]
- "Actualizar documento (PUT /workspaces/*)" — Opcional [✅ Activa if exists]
```

### Permission Mapping (complete reference)

| Selection | Bash Permission Pattern |
|-----------|------------------------|
| Listar workspaces | `Bash(curl *-X GET*api.clickup.com/api/v2/team)` |
| Listar spaces | `Bash(curl *-X GET*api.clickup.com/api/v2/team/*/space*)` |
| Listar folders | `Bash(curl *-X GET*api.clickup.com/api/v2/space/*)` |
| Listar lists | `Bash(curl *-X GET*api.clickup.com/api/v2/folder/*)` |
| Ver tasks numa list | `Bash(curl *-X GET*api.clickup.com/api/v2/list/*)` |
| Ver task/comentários | `Bash(curl *-X GET*api.clickup.com/api/v2/task/*)` |
| Criar ticket | `Bash(curl *-X POST*api.clickup.com/api/v2/list/*)` |
| Actualizar ticket | `Bash(curl *-X PUT*api.clickup.com/api/v2/task/*)` |
| Comentários/anexos/tags | `Bash(curl *-X POST*api.clickup.com/api/v2/task/*)` |
| Dependências (v5.0) | `Bash(curl *-X POST*api.clickup.com/api/v2/task/*/dependency*)` |
| Remover dependência (v5.0) | `Bash(curl *-X DELETE*api.clickup.com/api/v2/task/*/dependency*)` |
| Remover tag | `Bash(curl *-X DELETE*api.clickup.com/api/v2/task/*)` |
| Timer/time entries | `Bash(curl *-X POST*api.clickup.com/api/v2/team/*)` |
| Criar folder | `Bash(curl *-X POST*api.clickup.com/api/v2/space/*)` |
| Actualizar folder | `Bash(curl *-X PUT*api.clickup.com/api/v2/folder/*)` |
| Criar list | `Bash(curl *-X POST*api.clickup.com/api/v2/folder/*)` |
| Actualizar list | `Bash(curl *-X PUT*api.clickup.com/api/v2/list/*)` |
| Ler documentos/chat v3 | `Bash(curl *-X GET*api.clickup.com/api/v3/workspaces/*)` |
| Criar documento v3 | `Bash(curl *-X POST*api.clickup.com/api/v3/workspaces/*)` |
| Actualizar documento v3 | `Bash(curl *-X PUT*api.clickup.com/api/v3/workspaces/*)` |
| Evidence gate: git log (v5.0) | `Bash(git log*--grep*)` |

### Save Permissions

Read `SETTINGS_PATH`, then **REPLACE** all ClickUp permissions (not merge).

**CRITICAL — REPLACE logic:** Remove all existing entries containing `api.clickup.com` from `permissions.allow`, then add the newly selected ones. Keep all non-ClickUp permissions intact.

```python
# Pseudocode:
existing = settings["permissions"]["allow"]  # may not exist
non_clickup = [p for p in existing if "api.clickup.com" not in p]
new_clickup = [selected permissions from Pages 1-2]
settings["permissions"]["allow"] = non_clickup + new_clickup
```

This ensures that:
- Deselected permissions are **removed** (not just ignored)
- Non-ClickUp permissions (e.g., other tools) are preserved
- The final state matches exactly what the user selected

Use the Edit tool to update the JSON file.

### Warn about missing essentials

If user did NOT select these essential operations, warn them:
- `GET /team` and `GET /team/*/space*` (needed for setup navigation)
- `GET /space/*` and `GET /folder/*` and `GET /list/*` (needed for setup navigation)
- `POST /list/*/task` (needed to create tickets)
- `PUT /task/*` (needed to update ticket descriptions)
- `POST /task/*/dependency` and `DELETE /task/*/dependency` (v5.0: cascade blocking in QA)
- `git log --grep` (v5.0: evidence gate commit verification)

```
"⚠️ Atenção: Não autorizaste [operation]. O bot vai pedir permissão manual em cada execução para esta operação."
```

## Step 6: Install Auto-Approve Hook

The `Bash(curl *)` permission patterns only match single-command Bash calls. ClickUp API operations use multi-statement scripts (variable assignments, JSON payloads, response extraction with grep), which don't match those patterns. A **PreToolUse hook** is required to auto-approve these scripts.

The hook is a **template** bundled with the plugin at `hooks/clickup-auto-approve.sh`. It must be **installed** to the user's hooks directory with `__SETTINGS_PATH__` replaced — this is NOT a plugin-bundled hook (unlike `hooks/hooks.json`).

**Three complementary hook systems (v5.2.4):**
- `hooks/hooks.json` (plugin-bundled, auto-loaded): Agent/SendMessage/Write/Edit/Read + Bash matchers for orchestration, file ops, and safe git/test commands
- `hooks/bash-safe-auto-approve.sh` (bundled, loaded via hooks.json): Bash auto-approve for git read-only ops, git staging, commits, test runners — deny-list first, whitelist second
- `clickup-auto-approve.sh` (installed via setup wizard): Bash matcher for curl commands to ClickUp API — reads user's `settings.json` permissions dynamically

**All three are needed.** The hooks.json handles tool-level + git/test auto-approval. The auto-approve script handles Bash(curl) auto-approval with user-configured permission patterns.

**Version update (v5.2.4):** If the installed hook is outdated (from a previous plugin version), Step 6.0 detects the version mismatch and offers to re-install from the latest template.

**IMPORTANT:** The hook reads permissions from `settings.json` — it only approves operations the user authorized in Step 5. Anything not in the `permissions.allow` list still requires manual approval.

**IMPORTANT:** settings.json hooks are loaded dynamically — no session restart needed.

### 6.0 Hook version check (v5.2.4)

Check if an existing hook needs updating:

```
# Use the Read TOOL (not bash) to check hook version:
Read("{HOOKS_DIR}/clickup-auto-approve.sh")
Read("{PLUGIN_BASE_DIR}/hooks/clickup-auto-approve.sh")
# Compare content (ignoring the SETTINGS_PATH= line) to detect if outdated.
# If files differ beyond SETTINGS_PATH: offer to update.
```

If outdated, ask user:
```
AskUserQuestion: "Hook auto-approve existente está desactualizado (versão anterior do plugin). Actualizar para a versão actual?"
Options:
- "Sim, actualizar" (Recommended — mantém permissões configuradas)
- "Não, manter versão actual"
```

If user confirms update: re-run Step 6.1 (copy template + replace `__SETTINGS_PATH__`).
If hook doesn't exist: proceed to Step 6.1 normally (first install).

### 6.1 Copy and configure hook script

Determine the hooks directory from `SETTINGS_PATH` (same parent directory):
- `$HOME/.claude/settings.json` → `$HOME/.claude/hooks/`
- `$HOME/.claude-personal/settings.json` → `$HOME/.claude-personal/hooks/`
- `$PWD/.claude/settings.json` → `$PWD/.claude/hooks/`

The hook template has a placeholder `__SETTINGS_PATH__` that MUST be replaced with the actual `SETTINGS_PATH` detected in Step 1. This ensures the hook reads permissions from the correct settings.json (critical when multiple Claude Code installations exist).

```bash
mkdir -p {HOOKS_DIR}
sed 's|__SETTINGS_PATH__|{SETTINGS_PATH}|g' {PLUGIN_BASE_DIR}/hooks/clickup-auto-approve.sh > {HOOKS_DIR}/clickup-auto-approve.sh
chmod +x {HOOKS_DIR}/clickup-auto-approve.sh
```

Where `{PLUGIN_BASE_DIR}` is the directory containing `skills/`, `agents/`, `hooks/`, and `README.md`.

### 6.2 Register hook in settings.json

Add to `hooks.PreToolUse` array in `SETTINGS_PATH` (MERGE — do NOT overwrite existing hooks):

```json
{
  "matcher": "Bash",
  "hooks": [
    {
      "type": "command",
      "command": "{HOOKS_DIR}/clickup-auto-approve.sh"
    }
  ]
}
```

**Check for duplicates:** If a hook with `clickup-auto-approve` already exists, update the path instead of adding a new entry.

## Step 7: Local Cache Gitignore

Ensure `.claude/code-reviews/` is in the project's `.gitignore` to prevent accidentally committing cached ticket data.

```bash
if ! grep -q 'code-reviews/' .gitignore 2>/dev/null; then
  echo '.claude/code-reviews/' >> .gitignore
  echo "Added .claude/code-reviews/ to .gitignore"
else
  echo ".claude/code-reviews/ already in .gitignore"
fi
```

**Why:** The local cache contains ticket descriptions, frontmatter with sync state, and potentially sensitive review data. It should never be committed.

---

## Setup Complete

After all 7 steps, present summary:

```markdown
## ✅ Setup Completo

| Configuração | Valor |
|-------------|-------|
| Settings file | {SETTINGS_PATH} |
| API Token | pk_****{last4} |
| Workspace | {workspace_name} (ID: {workspace_id}) |
| List | {list_name} (ID: {list_id}) |
| Shortname | {shortname} |
| Permissões | {count}/18 autorizadas |
| Hook | ✅ Instalado em {HOOKS_DIR} |
| Local cache | ✅ `.claude/code-reviews/` em .gitignore |

Tudo pronto! Usa `/clickup-code-review` para lançar o code review.
```
