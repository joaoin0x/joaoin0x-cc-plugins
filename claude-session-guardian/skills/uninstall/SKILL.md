---
name: uninstall
description: Revert the claude-session-guardian setup by restoring settings.json from the backup created during /session-guardian:setup, and optionally removing the state directory. Does not remove the plugin files themselves.
---

# /session-guardian:uninstall

Reverte a configuração feita por `/session-guardian:setup`.

## Procedimento

### PASSO 1 — AskUserQuestion (destrutivo — confirmar)

```
AskUserQuestion TOOL:
  question: "Remover configuração do session-guardian? Vai restaurar settings.json do backup pré-setup. Queres também apagar state local (checkpoints, logs)?"
  header: "Uninstall"
  options: [
    { label: "Restaurar settings + apagar state", description: "Remoção completa: settings.json revertido + ~/.claude/session-guardian/ apagado" },
    { label: "Apenas restaurar settings", description: "Reverte settings.json mas mantém checkpoints/logs em ~/.claude/session-guardian/" },
    { label: "Cancelar", description: "Não fazer nada" }
  ]
  multiSelect: false
```

Se "Cancelar": return.

### PASSO 2 — Detectar settings.json

Mesmo processo do `/session-guardian:setup`:
1. `$CLAUDE_CONFIG_DIR/settings.json`
2. `~/.claude-personal/settings.json`
3. `~/.claude/settings.json`

```
SETTINGS_PATH = <path detectado>
BACKUP_PATH = "${SETTINGS_PATH}.pre-session-guardian"

Bash (single): [ -f "$BACKUP_PATH" ] && echo "OK" || echo "MISSING"
  Se MISSING:
    Emitir: "[session-guardian] Backup não encontrado em $BACKUP_PATH.
             Não é possível restaurar automaticamente. Edita $SETTINGS_PATH manualmente
             para remover o statusLine.command do session-guardian."
    Se resposta == "Restaurar settings + apagar state": continuar para PASSO 4 na mesma (apagar state).
    Se resposta == "Apenas restaurar settings": return.
```

### PASSO 3 — Restaurar backup

```
Bash (single): cp "$BACKUP_PATH" "$SETTINGS_PATH"
Bash (single): sync
Bash (single): jq empty "$SETTINGS_PATH" 2>/dev/null && echo "OK" || echo "INVALID"
  Se INVALID: reportar erro, não continuar.

Bash (single): rm -f "$BACKUP_PATH"
(backup consumido; deixar limpo para futuros setups).
```

### PASSO 4 — Apagar state (se opção escolhida)

Se resposta == "Restaurar settings + apagar state":

```
Bash (single): rm -rf "$HOME/.claude/session-guardian"
  (checkpoints, logs, flags — tudo.)
```

### PASSO 5 — Cancelar qualquer cron activo

```
Invocar CronList TOOL.
Filtrar tasks cujo prompt contenha "/session-guardian" ou "session-guardian" ou texto do prompt defensivo de retoma ("janela de 5 horas do Claude Code foi renovada").

Para cada task encontrada:
  CronDelete TOOL: task_id=<id>

Reportar quantas tasks foram canceladas.
```

### PASSO 6 — Confirmar ao utilizador

```
Emitir resumo:
"✓ Uninstall session-guardian completo.

  settings.json restaurado a partir de: $BACKUP_PATH
  State apagado: <sim/não> ($HOME/.claude/session-guardian/)
  Crons cancelados: <N>

  PRÓXIMOS PASSOS:
    1. /reload-plugins (para limpar skill/hook registrations)
    2. Abrir nova sessão (statusline volta ao config anterior)

  Os ficheiros do plugin em $CLAUDE_PLUGIN_ROOT NÃO foram removidos.
  Para remover o plugin propriamente dito: usa /plugin menu."
```

## Notas

- Uninstall é **additivo-safe**: não apaga ficheiros do plugin, só reverte config do utilizador.
- Se backup não existe (ex: utilizador apagou manualmente), uninstall reporta mas não força restore com dados que pode desconhecer.
- Crons de retoma agendados por HARD STOP prévio são cancelados — caso contrário disparariam sem guardian instalado e podiam confundir o utilizador.
