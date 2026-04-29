---
name: start
description: Manual start of the session-guardian monitor or legacy /loop fallback. v1.1.0+ runs the monitor automatically via the plugin manifest, so this skill is rarely needed — useful when the user explicitly stopped monitoring and wants to reactivate, or when running on a host where plugin monitors are unsupported (Bedrock, Vertex AI, Foundry).
---

# /session-guardian:start

Activa monitorização do plafond na sessão actual. Em v1.1.0+, o monitor `rate-limit-watcher` arranca automaticamente via plugin manifest — esta skill cobre os casos em que isso falha ou foi desactivado.

## Procedimento

### PASSO 1 — Detectar se monitor já está active

```
Invocar TaskList TOOL.
Filtrar tasks com command contendo "watch-rate-state.sh" OU description com "rate-limit-watcher".

Se encontrado E status="running":
  Emitir: "[session-guardian] Monitor 'rate-limit-watcher' já está active (task_id=<id>). Nada a fazer."
  Return.
```

### PASSO 2 — Detectar se host suporta monitors

```
Bash (single): echo "${ANTHROPIC_BEDROCK_BASE_URL:-}${ANTHROPIC_VERTEX_PROJECT_ID:-}${ANTHROPIC_FOUNDRY_BASE_URL:-}"

Se non-empty:
  HOST_SUPPORTS_MONITOR=0  (Bedrock/Vertex/Foundry — Monitor tool indisponível)
Senão:
  HOST_SUPPORTS_MONITOR=1
```

### PASSO 3a — Se host suporta monitor: re-arrancar via plugin reload

```
Se HOST_SUPPORTS_MONITOR=1:
  Output: "[session-guardian] O monitor v1.1.0 deveria ter arrancado automaticamente.
           Possíveis causas:
            - Plugin foi recém-instalado/actualizado e Claude Code não recarregou
            - Sessão arrancou antes de o setup estar completo
           Resolução:
            1. Executa /reload-plugins
            2. Se persistir, fecha esta sessão e abre uma nova"
  Return.
```

### PASSO 3b — Se host NÃO suporta monitor: fallback para /loop legacy

```
Se HOST_SUPPORTS_MONITOR=0:
  Limpar state antigo:
    Bash (single): rm -f "$SESSION_DIR/stop-requested.flag"

  Invocar /loop /session-guardian (dynamic mode — legacy fallback):
    Skill TOOL: skill="loop", args="/session-guardian"

  Output: "[session-guardian] Host não suporta plugin monitors (Bedrock/Vertex/Foundry).
           Fallback para skill /loop /session-guardian (modo polling, mais caro em tokens).
           Plafond actual: <pct>%. Reset em <minutes_local>."
```

### PASSO 4 — Reportar estado actual

```
CLAUDE_BASE = ${CLAUDE_CONFIG_DIR:-$HOME/.claude}
Read TOOL: $CLAUDE_BASE/session-guardian/rate-state.json
  Se existe:
    Output: "Plafond 5h actual: <pct>%, reset em <iso_local>."
  Se não existe:
    Output: "rate-state.json ainda não foi escrito (statusline escreverá no próximo turn ou refresh)."
```

## Notas

- **Idempotente**: invocar quando monitor já está active reporta sem efeitos.
- **v1.1.0 default**: utilizador raramente precisa desta skill — monitor arranca via manifest.
- **Hosts sem suporte**: Bedrock, Vertex AI, Microsoft Foundry. Nestes casos, fallback `/loop` é a única opção.
- **`/reload-plugins`**: solução mais comum quando monitor não arrancou após install/update.
