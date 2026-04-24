---
name: start
description: Manually start the session-guardian monitoring loop in the current Claude Code session. Useful when SessionStart hook auto-start failed, when the loop was previously stopped, or when the user wants to enable monitoring mid-session.
---

# /session-guardian:start

Arranca o loop de monitorização `/loop /session-guardian` nesta sessão.

## Procedimento

### PASSO 1 — Verificar se já está activo

```
Invocar CronList TOOL.
Procurar task cujo prompt contenha "/session-guardian" ou "session-guardian".

Se encontrado:
  Emitir: "[session-guardian] Loop já activo (task_id=<id>). Nada a fazer."
  Return.
```

### PASSO 2 — Limpar state antigo (defensivo)

```
Se $SESSION_DIR/stop-requested.flag existe:
  Bash (single): rm -f "$SESSION_DIR/stop-requested.flag"
  (consumida — utilizador quer arrancar agora)
```

### PASSO 3 — Arrancar o loop

Invocar skill `/loop` com prompt `"/session-guardian"` (dynamic mode — sem intervalo explícito, o guardian auto-ajusta):

```
Skill TOOL: skill="loop", args="/session-guardian"
```

Isto entrega ao skill /loop a instrução de correr `/session-guardian` em dynamic mode. O guardian toma conta a partir daí.

### PASSO 4 — Confirmar ao utilizador

Ler `~/.claude/session-guardian/rate-state.json` (se existir) para reportar estado actual:

```
Read TOOL: ~/.claude/session-guardian/rate-state.json
  Se existe:
    Extrair used_percentage_5h e resets_at_5h.
    Emitir: "[session-guardian] Loop arrancado. Plafond 5h actual: ${pct}%. Reset em ${resets_at}."
  Se não existe:
    Emitir: "[session-guardian] Loop arrancado. (rate-state.json ainda não foi escrito — statusline escreverá no próximo turn.)"
```

## Notas

- Idempotente: invocar quando já está activo não causa dano, apenas reporta.
- Não requer `/session-guardian:setup` prévio — pode correr mesmo sem statusline configurado (mas sem estado, o guardian vai para modo defensivo aos 2 min).
- Se o plugin ainda não foi setup (statusline não aponta para o script), o comando arranca o loop mas o guardian nunca vai ter dados reais — avisa o utilizador.
