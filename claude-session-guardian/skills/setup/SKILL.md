---
name: setup
description: Auto-configure the claude-session-guardian statusline by rewriting settings.json statusLine.command to point to the plugin's statusline script. One-time setup after plugin install. Backs up the existing settings.json first; performs atomic write; validates JSON; restores backup on failure.
---

# /session-guardian:setup

Configuração automática do statusline após instalar o plugin.

## Objectivo

- Descobrir o path absoluto do script `statusline/session-guardian-statusline.sh` dentro do plugin instalado
- Actualizar `statusLine.command` no `settings.json` do utilizador para apontar para esse path
- Backup atómico antes de qualquer mutação
- Validação JSON do resultado (restaura backup se inválido)
- Criar directórios base em `~/.claude/session-guardian/`

## Procedimento

### PASSO 1 — Descobrir plugin root e script path

```
Bash (single): echo "$CLAUDE_PLUGIN_ROOT"
  → Deve retornar algo como /Users/joao/.claude/plugins/.../claude-session-guardian
  → Se vazio: ABORTAR com mensagem "CLAUDE_PLUGIN_ROOT não está disponível neste contexto. Setup requer invocação como skill do plugin."

STATUSLINE_SCRIPT="$CLAUDE_PLUGIN_ROOT/statusline/session-guardian-statusline.sh"

Bash (single): [ -f "$STATUSLINE_SCRIPT" ] && echo "OK" || echo "MISSING"
  → Se MISSING: ABORTAR. Plugin install possivelmente incompleto.
```

### PASSO 2 — Garantir que o script é executável

```
Bash (single): chmod +x "$STATUSLINE_SCRIPT"
Bash (single): [ -x "$STATUSLINE_SCRIPT" ] && echo "OK" || echo "FAIL"
```

### PASSO 3 — Detectar settings.json correcto

Tentar por ordem:
1. `$CLAUDE_CONFIG_DIR/settings.json` (se variável definida)
2. `~/.claude-personal/settings.json` (instalação CLDP)
3. `~/.claude/settings.json` (instalação CLDW/default)

```
Bash (single): echo "$CLAUDE_CONFIG_DIR"
  → Se não vazio: SETTINGS_PATH="$CLAUDE_CONFIG_DIR/settings.json"
  → Se vazio: tentar os fallbacks.

Bash (single): [ -f "$SETTINGS_PATH" ] && echo "OK" || echo "MISSING"
  → Se MISSING: ABORTAR. "settings.json não encontrado em $SETTINGS_PATH. Define CLAUDE_CONFIG_DIR ou passa o path manualmente."
```

### PASSO 4 — Backup atómico

```
BACKUP_PATH="${SETTINGS_PATH}.pre-session-guardian"

Bash (single): cp "$SETTINGS_PATH" "$BACKUP_PATH"
Bash (single): sync
Bash (single): [ -f "$BACKUP_PATH" ] && echo "OK" || echo "FAIL"
  → Se FAIL: ABORTAR. Não continuar sem backup.
```

### PASSO 5 — Mutação atómica do settings.json

**OBRIGATÓRIO — usar jq, nunca sed/awk sobre JSON:**

```
Bash (single): TMP="${SETTINGS_PATH}.tmp.$$"

Bash (single): jq --arg cmd "$STATUSLINE_SCRIPT" '.statusLine = {type: "command", command: $cmd, padding: 0}' "$SETTINGS_PATH" > "$TMP"

Bash (single): [ -s "$TMP" ] && echo "OK" || echo "EMPTY"
  → Se EMPTY: rm $TMP, restaurar backup, ABORTAR.

Bash (single): jq empty "$TMP" 2>/dev/null && echo "VALID" || echo "INVALID"
  → Se INVALID: rm $TMP, restaurar backup, ABORTAR.

Bash (single): chmod 0600 "$TMP"
Bash (single): mv -f "$TMP" "$SETTINGS_PATH"
```

### PASSO 6 — Validação pós-escrita

```
Bash (single): jq -r '.statusLine.command' "$SETTINGS_PATH"
  → Deve retornar o path completo do statusline script.
  → Se não bater com $STATUSLINE_SCRIPT: restaurar backup, reportar erro.
```

### PASSO 7 — Criar directórios base

```
Bash (single): mkdir -p "$HOME/.claude/session-guardian/checkpoints"
Bash (single): chmod 0700 "$HOME/.claude/session-guardian"
```

### PASSO 8 — Confirmar ao utilizador

```
Emitir mensagem:
"✓ Setup session-guardian completo.

Config escrita em: $SETTINGS_PATH
Backup em:         $BACKUP_PATH
Statusline script: $STATUSLINE_SCRIPT

PRÓXIMOS PASSOS:
  1. /reload-plugins
  2. Abrir nova sessão Claude Code
  3. O SessionStart hook vai pedir ao modelo para invocar /session-guardian:start
     (ou invoca manualmente se auto-start falhar)

Para desinstalar: /session-guardian:uninstall"
```

## Restauro em caso de falha

Se qualquer passo 4-6 falha:

```
Bash (single): cp "$BACKUP_PATH" "$SETTINGS_PATH"
Bash (single): rm -f "${SETTINGS_PATH}.tmp.$$"

Emitir erro com detalhe do passo que falhou.
```

## Notas de segurança

- Nunca aceitar path para `settings.json` que contenha `..` ou que não esteja dentro de `$HOME`.
- Validar que `$CLAUDE_PLUGIN_ROOT` é um path absoluto existente antes de o usar.
- Permissões 0600 no settings.json resultante (preservar permissões originais se mais restritivas).
