---
name: react
description: Reactor invoked when the rate-limit-watcher monitor emits a notification. Decides action by zone (5h) or weekly status (7d) and executes atomically. Critical-zone HARD STOP is atomic with CronCreate-first ordering so resume is guaranteed even if subagent SendMessage or checkpoint write fails. Tracks consecutive errors so detector can self-pause if session is monthly-limit-blocked.
---

# /session-guardian:react

Reactor para notifications do detector. Recebe args `<zone> <pct> <mins_left>` ou `<kind> <pct_7d> weekly`.

## Paths

```
CLAUDE_BASE         = ${CLAUDE_CONFIG_DIR:-$HOME/.claude}
STATE_DIR           = $CLAUDE_BASE/session-guardian
RATE_STATE          = $STATE_DIR/rate-state.json
SESSION_ID          = ${CLAUDE_SESSION_ID:-<md5(cwd|PPID)[:12]>}
SESSION_DIR         = $STATE_DIR/$SESSION_ID
CHECKPOINT          = $STATE_DIR/checkpoints/$SESSION_ID/checkpoint.md
REACTOR_STATUS_FILE = $STATE_DIR/.reactor-status   (consecutive error count)
```

## Princípios fundamentais (v1.1.2)

1. **CronCreate FIRST em HARD STOP**: agendar retoma é o passo mais importante. Se SendMessage ou checkpoint falharem, retoma ainda acontece. CronCreate primeiro garante isto.
2. **Sem polling de TaskList**: 1 single check, marcar tudo o resto como "in-flight". Polling causou stream-idle timeout de 15min no incidente de 30 Apr.
3. **Operações em paralelo onde possível**: SendMessage a múltiplos subagents em parallel tool calls (1 turn).
4. **Error tracking**: ao falhar (qualquer step), incrementar `$REACTOR_STATUS_FILE`. Ao succeeder fully, escrever 0.
5. **Single Bash em paths leves**: green / RESET_DETECTED / weekly não devem usar 7+ Bash calls. Consolidar em 1 single Bash quando possível.
6. **Cadence adaptive vem do detector**: o reactor NÃO decide quando voltar a correr. Próxima invocação vem da próxima notification do detector (que poll com cadence apropriada à zona actual).

## Procedimento

### PASSO 0 — Parse args

```
$ARGUMENTS pode ser:
  - "<zone> <pct> <mins>"           5h ZONE_UPGRADE (yellow/red/critical)
  - "<zone> <pct> <mins> reset"     5h RESET_DETECTED (post-reset cleanup signal)
  - "<kind> <pct_7d> weekly"        7d notification (WEEKLY_WARN / WEEKLY_CRITICAL)

Se 4º arg == "reset" → RESET path. Saltar para PASSO 4-RESET.
Senão se 3º arg == "weekly" → WEEKLY path. Saltar para PASSO 4-WEEKLY.
Senão → 5H ZONE_UPGRADE path.
```

### PASSO 1 — Lock anti-race

```
Bash (single): mkdir -p "$SESSION_DIR"
Bash (single): if [ -f "$SESSION_DIR/react.lock" ]; then echo "BUSY"; else echo "$$" > "$SESSION_DIR/react.lock"; echo "ACQUIRED"; fi

Se BUSY: outra invocação a processar. Return sem acção.
```

### PASSO 2 — Ler rate-state (source of truth)

```
Read TOOL: $RATE_STATE

Se ficheiro ausente OU updated_at > 5min atrás:
  Output: "[session-guardian] React invocado mas rate-state ausente/stale.
           Diagnóstico via $STATE_DIR/statusline-errors.log."
  Bash (single): rm -f "$SESSION_DIR/react.lock"
  Increment_error  (PASSO 7)
  Return.

PCT     = .used_percentage_5h
PCT_7D  = .used_percentage_7d
RESETS  = .resets_at_5h
```

### PASSO 3 — Determinar zona ACTUAL (validar contra args)

```
zone_for_pct():
  pct < 50         → green
  pct 50-64        → green-high
  pct 65-74        → yellow      (SOFT WARN — v1.1.1: shifted from 70)
  pct 75-84        → red         (HARD WARN — v1.1.1: shifted from 82)
  pct >= 85        → critical    (HARD STOP — v1.1.1: shifted from 90)

ZONE = zone_for_pct(PCT)
MINS = mins_until_reset(RESETS) via epoch math (helper inline ou via Bash)
```

### PASSO 4 — Switch por ZONE

#### `green` ou `green-high` — silent no-op

(Em v1.1.2 o detector NÃO emite mais ZONE_UPGRADE para green/green-high — só
para yellow/red/critical. Esta branch só é alcançada em casos exóticos, ex:
init com pct already > 0. Tratamento minimalista para evitar custo de turn.)

```
Single Bash consolidado:
  rm -f "$SESSION_DIR/react.lock"
  echo "0" > "$REACTOR_STATUS_FILE"
  echo "$(date -u +%FT%TZ) | react | green | quiet-noop" >> "$SESSION_DIR/monitor.log"

Sem output ao user. Return.
```

#### `yellow` (SOFT WARN, 65-74%) — Aviso

```
Se NÃO existe $SESSION_DIR/soft-warn-sent.flag:
  Output: "[session-guardian] ⚠ Plafond 5h a ${PCT}% — zona amarela.
           ${MINS} min até reset. HARD STOP automático aos 85%.
           Considera não iniciar novos waves / skills pesadas."
  Bash (single): touch "$SESSION_DIR/soft-warn-sent.flag"

(Se flag existe — health pulse repetido — silent.)

Reset error count.
rm react.lock. Return.
```

#### `red` (HARD WARN, 75-84%) — Aviso urgente

```
Se NÃO existe $SESSION_DIR/hard-warn-sent.flag:
  [CANAL 1] Output:
    "[session-guardian] 🔴 Plafond 5h a ${PCT}% — ZONA VERMELHA.
     ${MINS} min até reset. HARD STOP iminente aos 85%.
     Termina waves em curso. NÃO inicies novos."

  [CANAL 2] CONDICIONAL — só se houver subagents activos:
    Bash (single): TaskList | jq '[.[] | select(.status != "completed")] | length' 2>/dev/null
    Se > 0:
      Para cada subagent activo (PARALLEL tool calls):
        SendMessage(to=<name>, message="Plafond 5h a ${PCT}%. NÃO inicies novas
        tarefas. Avalia se é seguro parar em checkpoint. HARD STOP aos 85%.")

  [CANAL 3] PushNotification se disponível.

  Bash (single): touch "$SESSION_DIR/hard-warn-sent.flag"

Reset error count.
rm react.lock. Return.
```

#### `critical` (HARD STOP, ≥85%) — Atomic pause sequence

**ORDEM CRÍTICA (não saltar passos, não paralelizar fases):**

```
4.1 PAUSE LOCK
  Bash (single): if [ -f "$SESSION_DIR/pause.lock" ]; then echo BUSY; else echo "$$" > "$SESSION_DIR/pause.lock"; echo OK; fi
  Se BUSY: HARD STOP já em curso — rm react.lock, return.

4.2 CALCULAR resume_at + cron expr (FIRST — agendar antes de tudo)
  Bash (single):
    RESUME_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "${RESETS%Z}" "+%s") + 300
    Em local TZ:
      MINUTE=$(date -r $RESUME_EPOCH +%M)
      HOUR=$(date -r $RESUME_EPOCH +%H)
      DAY=$(date -r $RESUME_EPOCH +%d)
      MONTH=$(date -r $RESUME_EPOCH +%m)
    Se MINUTE == "00" ou "30": MINUTE+=3 (jitter avoidance)
    cron_expr = "$MINUTE $HOUR $DAY $MONTH *"

  VALIDATION: se RESUME_EPOCH <= now+60s (reset já passou ou iminente):
    Output: "[session-guardian] HARD STOP abortado — reset_at já passou
             (sliding window?). Cleanup defensivo + manual resume necessário."
    Bash (parallel): rm -f $SESSION_DIR/{pause,react}.lock; rm -f $SESSION_DIR/{soft,hard}-warn-sent.flag
    Increment error (PASSO 7).
    Return.

4.3 CRONCREATE FIRST (insurance — retoma garantida)
  CronCreate({
    cron: <cron_expr>,
    prompt: <PROMPT_DEFENSIVO_RETOMA — ver secção abaixo>,
    recurring: false
  })

  Se erro:
    Tentar com recurring=true + adicionar self-CronDelete no início do prompt.
    Se ainda erro: Output erro claro, increment error, abortar HARD STOP.

  Guardar CRON_ID retornado.

4.4 IDENTIFICAR + ALERTAR SUBAGENTS (1 single check, no polling)
  Bash (single): TaskList | jq '[.[] | select(.status != "completed")] | length'

  Se > 0:
    Para cada subagent (PARALLEL tool calls — 1 turn):
      SendMessage(to=<name>, message="PAUSA ASAP. Plafond 5h a ${PCT}% —
      HARD STOP automático. Não inicies nova tarefa nem continues esta.
      Reporta idle imediatamente. Escreve estado parcial a disco antes
      de parar. Retoma automática agendada para ${resume_at_local} via
      cron (id=${CRON_ID}).")

  NÃO fazer polling. Subagents que não confirmem em 30s são marcados
  "in-flight" no checkpoint. Confiamos no CronCreate para retoma.

4.5 WRITE CHECKPOINT (com cron_id já definido)
  Write TOOL: $CHECKPOINT (mkdir parent if needed)
  Conteúdo:
    ---
    paused_at: <ISO UTC now>
    resume_at: <ISO UTC = RESUME_EPOCH>
    cron_id: <CRON_ID>
    used_percentage_at_pause: <PCT>
    workflow_active: <inferir de TaskList + contexto recente>
    project_dir: <$CLAUDE_PROJECT_DIR>
    session_id: <$SESSION_ID>
    ---

    # Checkpoint — <timestamp local>

    ## Subagents activos ao pausar
    | ID | Nome | Status | Última SendMessage |
    |---|---|---|---|
    (linha por subagent — todos marcados "in-flight" excepto se TaskList
    showed "completed" nesse exacto momento)

    ## Contexto do workflow
    <Texto livre baseado em TaskList + mensagens recentes>

4.6 CLEANUP + OUTPUT FINAL
  Bash (parallel):
    rm -f "$SESSION_DIR/soft-warn-sent.flag"
    rm -f "$SESSION_DIR/hard-warn-sent.flag"
    rm -f "$SESSION_DIR/pause.lock"
    rm -f "$SESSION_DIR/react.lock"
    echo "0" > "$REACTOR_STATUS_FILE"  (reset error count — sucesso)

  Output:
    "[session-guardian] 🛑 PAUSA ACTIVA.
     Plafond 5h ${PCT}% — HARD STOP accionado.
     Cron de retoma: id=${CRON_ID}, dispara <resume_at_local>.
     Checkpoint: $CHECKPOINT
     SendMessages emitidas: <N> subagents alertados.
     MANTÉM O TERMINAL ABERTO (cron é session-scoped)."
```

### PASSO 4-RESET — Cleanup pós-reset (NOVO v1.1.2)

Disparado pelo detector quando a zona transita de active (yellow/red/critical) para quiet (green/green-high). Substitui o "defensive cleanup via health pulse" da v1.1.0/1.1.1.

```
Single Bash consolidado (1 call, não múltiplos):
  HAD_FLAGS=0
  if [ -f "$SESSION_DIR/soft-warn-sent.flag" ]; then HAD_FLAGS=1; rm -f "$SESSION_DIR/soft-warn-sent.flag"; fi
  if [ -f "$SESSION_DIR/hard-warn-sent.flag" ]; then HAD_FLAGS=1; rm -f "$SESSION_DIR/hard-warn-sent.flag"; fi
  rm -f "$SESSION_DIR/react.lock"
  echo "0" > "$REACTOR_STATUS_FILE"
  echo "$(date -u +%FT%TZ) | react | reset-detected | from=<prev> to=${ZONE} pct=${PCT} | flags_cleaned=${HAD_FLAGS}" >> "$SESSION_DIR/monitor.log"

Se HAD_FLAGS=1:
  Output: "[session-guardian] ✓ Reset detectado (pct=${PCT}). Flags limpas — zona ${ZONE}."
Senão:
  (silent — caso comum quando HARD STOP / stop manual já tinham limpado)

Return.
```

### PASSO 4-WEEKLY — 7-day notifications

```
Se kind == "WEEKLY_WARN":
  Output: "[session-guardian] ⚠ Janela semanal (7d) a ${PCT_7D}% — zona de aviso.
           Avalia o trabalho restante para a semana. Atingir 100% bloqueia
           a sessão até reset semanal (potencialmente vários dias).
           Considera reduzir actividade ou planear pausa estratégica."

Se kind == "WEEKLY_CRITICAL":
  Output: "[session-guardian] 🚨 Janela semanal (7d) a ${PCT_7D}% — CRÍTICO.
           Hit 100% bloqueia a sessão até reset semanal (vários dias).
           Recomendação: parar trabalho não-essencial AGORA.
           Não há HARD STOP automático para 7d (não há retoma viável)."

Reset error count.
rm react.lock. Return.
```

### PASSO 7 — Error tracking helpers

**Increment_error (em qualquer abort/error path):**
```
Bash (single):
  cur=$(cat "$REACTOR_STATUS_FILE" 2>/dev/null || echo 0)
  echo $((cur + 1)) > "$REACTOR_STATUS_FILE"
```

**Reset_error (em sucesso):**
```
Bash (single): echo "0" > "$REACTOR_STATUS_FILE"
```

Se contador atinge `MAX_CONSECUTIVE_REACTOR_ERRORS=3`, o detector pára de emitir notifications (auto-pause silencioso). Recovery: `echo 0 > $REACTOR_STATUS_FILE` ou ao próximo reactor success.

### PASSO 8 — Append monitor.log (sempre, excepto early defensive return)

```
Bash (single): echo "$(date -u +%FT%TZ) | react | <zone_or_kind> pct=<P> mins=<M> | <action>" >> "$SESSION_DIR/monitor.log"
```

## Prompt defensivo de retoma (HARD STOP)

Inserido literal no `prompt` do CronCreate:

```
A janela 5h do Claude Code foi renovada. Antes da pausa havia workflow em curso.

PROCEDIMENTO OBRIGATÓRIO (NÃO saltar passos):

1. Read TOOL: <CHECKPOINT_PATH>
2. Interpreta o checkpoint: workflow, subagents, ultima SendMessage, wave/fase.
3. Para cada subagent listado (paused ou in-flight):
   SendMessage(to=<name>, message="Pausa terminou. Estado antes: <resumo>.
   Retoma de onde ficaste. Confirma quando pronto.")
4. Aguarda confirmacoes de subagents (max 3 min via TaskList — ou prossegue
   com os que confirmaram).
5. SO entao prosseguir o workflow original onde parou.

NAO E ACEITAVEL:
- "Vou verificar" sem actually Read TOOL no checkpoint.
- Plano sem executar passos 1-4.
- Compactar/resumir trabalho — retoma no ponto EXACTO.
- Iniciar nova fase antes de subagents confirmarem.

Se checkpoint corrupto/suspeito: PARA e pergunta ao utilizador.
```

## Notas de implementação

- **CronCreate primeiro é não-negociável**: foi a falha de 30 Apr. Se a sequência abortar entre SendMessage e CronCreate, retoma é perdida. Agendar primeiro garante que mesmo crashes posteriores deixam retoma agendada.
- **Sem polling**: o incidente mostrou que 15 min de polling matam a sessão por stream-idle. 1 single TaskList check + assume rest as in-flight é suficiente.
- **PARALLEL tool calls**: SendMessages a múltiplos subagents devem ser parallel (single message com múltiplos tool_use blocks). Reduz latência de N turns para 1.
- **Lock files com PID**: react.lock e pause.lock contêm PID. Em recuperação de crashes futuros, podemos validar PID vs `kill -0` para detectar locks stale.
- **Validation `RESUME_EPOCH <= now`**: cobre o caso onde reset já passou (sliding window) — abort HARD STOP em vez de criar cron no passado.
