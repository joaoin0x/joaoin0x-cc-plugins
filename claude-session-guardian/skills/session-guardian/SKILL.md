---
name: session-guardian
description: Monitor Claude Code 5-hour rate limit window via dynamic /loop. Graduated warnings (SOFT 70%, HARD 82%), cooperative pause + automatic resume at 90%. Adapts cadence based on workflow activity and computes time-to-reset via UTC epoch math (no clock-conversion errors).
---

# session-guardian skill

Monitor da janela 5h do Claude Code. Iteração leve via `/loop /session-guardian` (dynamic mode). Cada iteração lê estado, decide acção, agenda próximo check.

## Paths

```
CLAUDE_BASE     = ${CLAUDE_CONFIG_DIR:-$HOME/.claude}
STATE_DIR       = $CLAUDE_BASE/session-guardian
RATE_STATE      = $STATE_DIR/rate-state.json   (escrito pelo statusline)
SESSION_ID      = ${CLAUDE_SESSION_ID:-<md5(cwd|PPID)[:12]>}
SESSION_DIR     = $STATE_DIR/$SESSION_ID
CHECKPOINT      = $STATE_DIR/checkpoints/$SESSION_ID/checkpoint.md
```

## Helpers (executa inline em Bash quando precisares)

### `time_until_reset_seconds`
Comparação por epoch — ÚNICA forma correcta de calcular tempo até reset. NUNCA inferir por slope (causou bug grave em v1.0.7 onde skill iterou 18 min com cálculo errado).

```bash
RESETS_AT="$1"  # ISO-8601 UTC ex: "2026-04-28T02:30:00Z"
NOW_EPOCH=$(date -u +%s)
RESET_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "$RESETS_AT" "+%s" 2>/dev/null \
              || date -d "$RESETS_AT" "+%s" 2>/dev/null)
SECS_LEFT=$(( RESET_EPOCH - NOW_EPOCH ))
[ "$SECS_LEFT" -lt 0 ] && SECS_LEFT=0
MINS_LEFT=$(( SECS_LEFT / 60 ))
```

### `idle_workflow_check`
Decide se cadence pode ser relaxada. Workflow IDLE = sem subagents activos.

```bash
ACTIVE=$(TaskList | jq '[.[] | select(.status != "completed")] | length')
[ "${ACTIVE:-0}" -eq 0 ] && IDLE_MODE=1 || IDLE_MODE=0
```

## Fluxo (cada iteração)

### PASSO 0 — Session scope

```
mkdir -p $SESSION_DIR
SESSION_ID = como definido em "Paths"
```

### PASSO 0A — Stop check

```
SE existe $SESSION_DIR/stop-requested.flag:
  rm $SESSION_DIR/stop-requested.flag
  Output: "[session-guardian] Loop terminado (stop flag consumida)."
  NÃO ScheduleWakeup. Return.
```

### PASSO 1 — Ler rate-state

```
SE [ -L "$RATE_STATE" ]:
  Erro crítico (symlink). ScheduleWakeup(300, "symlink-detected"). Return.

Read TOOL: $RATE_STATE.

SE não existe OU updated_at > 5min atrás:
  → MODO DEFENSIVO (PASSO 1.5)
```

### PASSO 1.5 — Modo defensivo (só se rate-state ausente/stale)

PRINCÍPIO: dados ausentes = NUNCA acções destrutivas. Só CANAL 1 com diagnóstico específico.

Inspeccionar `$STATE_DIR/statusline-errors.log`:
- Se existe E mtime < 5min E últimas linhas contêm `invalid resets_at_5h: <integer>` → diagnóstico "binário em memória obsoleto" → sugestão "fechar sessão e abrir nova"
- Se existe E contém `is a symlink` → "ataque/configuração com symlink"
- Se existe E contém `cannot create`/`permission denied` → "permissões filesystem"
- Se NÃO existe ou inactivo → "statusline não está a ser invocado"

Output:
```
[session-guardian] ⚠ Modo defensivo
Diagnóstico: {DIAG}
Sugestão: {SUG}
NÃO disparado: SendMessage, HARD STOP, CronCreate.
Acções tuas: /usage, /session-guardian:stop, ou ler logs.
```

`ScheduleWakeup(120, "defensive: $DIAG"). Return.`

### PASSO 1.6 — Limpar flags em downgrade (NOVO v1.0.8)

```
SE $SESSION_DIR/soft-warn-sent.flag existe E pct < 70:
  rm $SESSION_DIR/soft-warn-sent.flag
  Output: "[session-guardian] ✓ Plafond desceu abaixo de 70%. Zona verde."

SE $SESSION_DIR/hard-warn-sent.flag existe E pct < 82:
  rm $SESSION_DIR/hard-warn-sent.flag
  Output: "[session-guardian] ✓ Saiu da zona vermelha (<82%). Mantém SOFT WARN se aplicável."
```

### PASSO 2 — Decidir delay (com IDLE_MODE)

Calcular `IDLE_MODE` (helper acima) e `MINS_LEFT` (helper acima).

| Condição | `next_delay_seconds` |
|---|---|
| pct < 50, IDLE_MODE=0 | 600 (10 min) |
| pct < 50, IDLE_MODE=1 | 1500 (25 min) — overhead-saving |
| pct 50–69, IDLE_MODE=0 | 180 (3 min) |
| pct 50–69, IDLE_MODE=1 | 600 (10 min) |
| pct 70–81, IDLE_MODE=0 | 120 (2 min) — SOFT WARN |
| pct 70–81, IDLE_MODE=1 | 300 (5 min) — SOFT WARN idle |
| pct 82–89, IDLE_MODE=0 | 60 (1 min) — HARD WARN |
| pct 82–89, IDLE_MODE=1 | 180 (3 min) — HARD WARN idle |
| pct ≥ 90 | HARD STOP (sem next_delay) |

**Adicional clamp**: se `MINS_LEFT < 10` E pct ≥ 70: forçar `next_delay_seconds = 60` independentemente de IDLE_MODE — última fase requer monitor apertado.

### PASSO 3 — Acção por threshold

#### pct < 70 — Passiva

```
Append log: "{ts} | pct={pct}% | passive | mins_left={MINS_LEFT} | idle={IDLE_MODE}"
ScheduleWakeup(next_delay_seconds, "monitor passive at ${pct}% (idle=${IDLE_MODE}, ${MINS_LEFT}min left)").
Return.
Output mínimo: "guardian: ${pct}% (${MINS_LEFT}min até reset)"
```

#### pct 70–81 — SOFT WARN

```
SE NÃO existe $SESSION_DIR/soft-warn-sent.flag:
  [CANAL 1] Output:
    "[session-guardian] ⚠ Plafond 5h a ${pct}% — zona amarela.
     ${MINS_LEFT} min até reset. HARD STOP aos 90%.
     Considera NÃO iniciar novos waves / skills pesadas."
  Write soft-warn-sent.flag.

Append log: "{ts} | pct={pct}% | soft-warn | mins_left={MINS_LEFT}"
ScheduleWakeup(next_delay_seconds, "soft warn at ${pct}% (${MINS_LEFT}min left)").
Return.
```

#### pct 82–89 — HARD WARN

```
SE NÃO existe $SESSION_DIR/hard-warn-sent.flag:
  [CANAL 1] Output:
    "[session-guardian] 🔴 Plafond 5h a ${pct}% — ZONA VERMELHA.
     ${MINS_LEFT} min até reset. HARD STOP aos 90%.
     Termina waves em curso. NÃO inicies novos."

  [CANAL 2] CONDICIONAL — só se IDLE_MODE=0:
    Para cada subagent activo (TaskList):
      SendMessage(to=<name>, message="Plafond 5h a ${pct}%. NÃO inicies novas tarefas.
        Se em tarefa longa, avalia se é seguro parar em checkpoint. HARD STOP aos 90%.")
  Se IDLE_MODE=1: Output adicional: "(CANAL 2 suprimido — workflow já idle)"

  [CANAL 3] PushNotification se disponível:
    title="Claude Code — plafond ${pct}%"
    body="HARD STOP iminente. ${MINS_LEFT} min até reset."
    Falha silenciosa se tool indisponível.

  Write hard-warn-sent.flag.

Append log: "{ts} | pct={pct}% | hard-warn | mins_left={MINS_LEFT} | idle={IDLE_MODE}"
ScheduleWakeup(next_delay_seconds, "hard warn at ${pct}% (idle=${IDLE_MODE}, ${MINS_LEFT}min left)").
Return.
```

#### pct ≥ 90 — HARD STOP

```
1. Lock: criar $SESSION_DIR/pause.lock com PID. Se já existe, return.

2. TaskList → subagents activos.

3. SendMessage a cada activo:
   "PAUSA ASAP. Não inicies nova tarefa nem continues esta. Reporta idle.
    Escreve estado parcial a disco antes de parar. Retoma automática
    após reset 5h via SendMessage."

4. Polling TaskList a cada 10s, timeout 180s. Marcar paused/in-flight.

5. Write checkpoint em $CHECKPOINT (ver schema abaixo).

6. resume_at = $resets_at_5h + 5min. Converter para cron 5-field LOCAL TZ.
   Se minute ∈ {0, 30}: +3min para evitar jitter.

7. CronCreate one-shot:
   prompt = ver "Prompt defensivo de retoma"
   Tentar recurring=false; fallback recurring=true com self-CronDelete
   no início do prompt.

8. Parar próprio loop:
   A) CronList → CronDelete do task com prompt /session-guardian (não o novo)
   B) Fallback: write $SESSION_DIR/stop-requested.flag

9. rm $SESSION_DIR/{soft,hard}-warn-sent.flag
10. rm $SESSION_DIR/pause.lock

11. Output:
    "[session-guardian] 🛑 PAUSA ACTIVA.
     Plafond 5h ${pct}%. Retoma agendada para ${resume_at_local} (${MINS_LEFT}min).
     Checkpoint: ${CHECKPOINT}
     MANTÉM O TERMINAL ABERTO (cron é session-scoped)."

12. NÃO ScheduleWakeup.
```

### PASSO 4 — Auto-pause por overhead idle (NOVO v1.0.8)

Trigger: a skill detecta que está a iterar há muito tempo em workflow idle, com plafond na zona amarela ou vermelha mas estável (a iteração consome ~1pp/min só com o overhead do próprio loop).

```
SE IDLE_MODE=1
   E pct ≥ 70 (zona amarela ou vermelha)
   E MINS_LEFT > 30 (ainda demora ao reset)
   E últimas 5 entradas de monitor.log mostram pct estável (slope < 0.3pp/min):

  → AUTO-PAUSE (não é HARD STOP, é shutdown preventivo do loop)
    Skill decide parar para não consumir plafond inutilmente.

  Procedimento:
  1. Output:
     "[session-guardian] 🟡 Auto-pause preventivo.
      Workflow idle (sem subagents activos), plafond ${pct}% estável,
      reset em ${MINS_LEFT}min. O loop em si consumiria ~${MINS_LEFT}pp
      durante esse tempo. Vou parar e agendar retoma para após reset."

  2. CronCreate one-shot para resume_at = resets_at_5h + 5min:
     prompt: "/session-guardian:start"
     (prompt simples — só re-arranca o monitor; nenhum workflow para
      retomar porque IDLE_MODE=1, nada para checkpoint)

  3. Append log: "{ts} | pct={pct}% | AUTO-PAUSE-IDLE | cron-id={cron_id}"

  4. Parar loop (mesmo fallback que HARD STOP passo 8).

  5. Output final:
     "Loop pausado. Cron de re-arranque agendado para ${resume_at_local}.
      Para cancelar: CronDelete ${cron_id}."

  6. NÃO ScheduleWakeup.
```

**Distinção crítica**: AUTO-PAUSE-IDLE ≠ HARD STOP. Não há subagents para pausar (já estão idle), não há checkpoint de workflow (não há workflow). Só agenda re-arranque do monitor.

## Schema do checkpoint (PASSO 3 ≥90%)

```yaml
---
paused_at: <ISO UTC>
resume_at: <ISO UTC, = resets_at_5h + 5min>
used_percentage_at_pause: <int>
cron_id: <8-char>
workflow_active: <inferido de TaskList + contexto recente>
project_dir: <$CLAUDE_PROJECT_DIR>
session_id: <$SESSION_ID>
---

# Checkpoint — {timestamp local}

## Subagents activos ao pausar

| ID | Nome | Status | Última SendMessage |
|---|---|---|---|
| ... | ... | paused/in-flight | ... |

## Contexto do workflow

Texto livre — workflow + wave + ticket em curso, etc.
```

## Prompt defensivo de retoma (HARD STOP only)

Inserir literal no `prompt` do `CronCreate` (com placeholders substituídos):

```
A janela 5h do Claude Code foi renovada. Antes da pausa havia workflow em curso.

PROCEDIMENTO OBRIGATÓRIO (NÃO saltar passos):

1. Read TOOL: {CHECKPOINT_PATH}
2. Interpreta o checkpoint: workflow, subagents, última SendMessage, wave/fase.
3. Para cada subagent listado (paused ou in-flight):
   SendMessage(to=<name>, message="Pausa terminou. Estado antes: {resumo}.
   Retoma de onde ficaste. Confirma quando pronto.")
4. Aguarda confirmações (max 3min via TaskList polling).
5. Recriar loop: /session-guardian:start
6. SÓ então prosseguir o workflow original onde parou.

NÃO É ACEITÁVEL:
- "Vou verificar" sem actualmente Read TOOL no checkpoint.
- Plano sem executar passos 1-5.
- Compactar/resumir o trabalho — retoma no ponto EXACTO.
- Iniciar nova fase antes de subagents confirmarem.

Se checkpoint corrupto/suspeito: PARA e pergunta ao utilizador.
```

## Notas de implementação

- `ScheduleWakeup` prompt SEMPRE `/loop /session-guardian` (re-entry).
- `reason` deve ser concreta para telemetria (`"hard warn at 84% (idle=1, 12min left)"`).
- I/O failure: emitir erro ao output, continuar — nunca interromper silenciosamente.
- Nunca revelar credenciais ou conteúdo sensível.
- **Tempo até reset**: SEMPRE via `time_until_reset_seconds` (epoch math). NUNCA por slope/dead-reckoning.
- **IDLE_MODE**: SEMPRE recalcular cada iteração (workflow pode mudar).
- **Flags downgrade**: SEMPRE verificar no PASSO 1.6 antes de decidir cadence.
