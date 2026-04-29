---
name: react
description: Reactor invoked when the rate-limit-watcher monitor emits a notification (ZONE_UPGRADE or HEALTHY). Reads current rate-state, decides action based on zone (none, SOFT WARN, HARD WARN, HARD STOP), and executes. Accepts args "<zone> <pct> <mins_left>" via $ARGUMENTS but always validates against rate-state.json for freshness. Includes defensive flag cleanup in green zones (post-reset edge case).
---

# /session-guardian:react

Skill invocada quando o monitor `rate-limit-watcher` emite uma notification. Decide a acção apropriada e executa.

## Paths

```
CLAUDE_BASE     = ${CLAUDE_CONFIG_DIR:-$HOME/.claude}
STATE_DIR       = $CLAUDE_BASE/session-guardian
RATE_STATE      = $STATE_DIR/rate-state.json
SESSION_ID      = ${CLAUDE_SESSION_ID:-<md5(cwd|PPID)[:12]>}
SESSION_DIR     = $STATE_DIR/$SESSION_ID
CHECKPOINT      = $STATE_DIR/checkpoints/$SESSION_ID/checkpoint.md
```

## Procedimento

### PASSO 0 — Parse args e session scope

```
$ARGUMENTS pode ser "<zone> <pct> <mins_left>" ou vazio.

Bash (single): mkdir -p "$SESSION_DIR"
Tentar parse $ARGUMENTS:
  ZONE_HINT  = arg 1 (green / green-high / yellow / red / critical)
  PCT_HINT   = arg 2 (integer 0-100)
  MINS_HINT  = arg 3 (integer or "?")

Se parse falha ou args ausentes: ZONE_HINT/PCT_HINT/MINS_HINT = vazio.
```

### PASSO 1 — Adquirir lock (anti-race)

```
Bash (single): [ -f "$SESSION_DIR/react.lock" ] && echo "BUSY" || echo "FREE"
Se BUSY: outro reactor já a processar — emitir aviso curto e return.
Se FREE: criar $SESSION_DIR/react.lock com PID actual.
```

### PASSO 2 — Ler rate-state actual (source of truth)

```
Read TOOL: $RATE_STATE

Se ficheiro não existe OU updated_at > 5min atrás:
  [DEFENSIVE — dados não fiáveis]
  Output: "[session-guardian] React invocado mas rate-state ausente/stale.
           Sem acção destrutiva. Verifica statusline."
  rm $SESSION_DIR/react.lock
  Return.

Extrair:
  PCT  = .used_percentage_5h
  RES  = .resets_at_5h
```

### PASSO 3 — Calcular zone actual + minutos até reset

```
Helper inline:
  zone_for_pct():
    pct < 50         → green
    pct 50-69        → green-high
    pct 70-81        → yellow
    pct 82-89        → red
    pct >= 90        → critical

  mins_until_reset(iso):
    epoch = date -j -u -f "%Y-%m-%dT%H:%M:%SZ" "${iso%Z}" "+%s" (BSD)
            || date -d "$iso" "+%s" (GNU)
    now = date -u +%s
    secs = epoch - now (clamp >= 0)
    return secs / 60

ZONE = zone_for_pct(PCT)
MINS = mins_until_reset(RES)
```

### PASSO 4 — Decidir acção pela ZONE

#### `green` ou `green-high` — Cleanup defensivo + log

Aplicado em transições "init → green-high" no arranque e em health pulses pós-reset.

```
Se existe $SESSION_DIR/soft-warn-sent.flag OU $SESSION_DIR/hard-warn-sent.flag:
  rm $SESSION_DIR/soft-warn-sent.flag  (silent if absent)
  rm $SESSION_DIR/hard-warn-sent.flag
  Output: "[session-guardian] ✓ Cleanup: flags antigas limpas (zone=${ZONE}, pct=${PCT}). Provável reset da janela 5h."

Senão (caso normal — health pulse em zona verde):
  (sem output ao user — reduzir ruído)
  Append log: "$(date -u +%FT%TZ) | react | ZONE=${ZONE} pct=${PCT} | quiet"

rm $SESSION_DIR/react.lock
Return.
```

#### `yellow` (SOFT WARN) — Aviso ao utilizador

```
Se NÃO existe $SESSION_DIR/soft-warn-sent.flag:
  [CANAL 1] Output:
    "[session-guardian] ⚠ Plafond 5h a ${PCT}% — zona amarela.
     ${MINS} min até reset. HARD STOP automático aos 90%.
     Considera não iniciar novos waves / skills pesadas."
  Write $SESSION_DIR/soft-warn-sent.flag

Se flag JÁ existe:
  (já avisado nesta janela; este invoke veio de health pulse — silent)

Append log: "$(date -u +%FT%TZ) | react | yellow pct=${PCT} mins=${MINS}"
rm $SESSION_DIR/react.lock
Return.
```

#### `red` (HARD WARN) — Aviso urgente + SendMessage condicional + push

```
Se NÃO existe $SESSION_DIR/hard-warn-sent.flag:
  [CANAL 1] Output:
    "[session-guardian] 🔴 Plafond 5h a ${PCT}% — ZONA VERMELHA.
     ${MINS} min até reset. HARD STOP iminente aos 90%.
     Termina waves em curso. NÃO inicies novos."

  [CANAL 2] CONDICIONAL — só se houver subagents activos:
    Bash (single): TaskList | jq '[.[] | select(.status != "completed")] | length'
    Se > 0:
      Para cada subagent activo:
        SendMessage(to=<name>,
          message="Plafond 5h a ${PCT}%. NÃO inicies novas tarefas. Se em
          tarefa longa, avalia se é seguro parar em checkpoint. HARD STOP
          iminente aos 90%.")
    Senão: Output adicional: "(CANAL 2 suprimido — workflow já idle)"

  [CANAL 3] PushNotification se disponível:
    title="Claude Code — plafond ${PCT}%"
    body="HARD STOP iminente. ${MINS} min até reset."
    Falha silenciosa se tool indisponível.

  Write $SESSION_DIR/hard-warn-sent.flag

Se flag JÁ existe:
  (já avisado nesta janela; health pulse — silent)

Append log: "$(date -u +%FT%TZ) | react | red pct=${PCT} mins=${MINS}"
rm $SESSION_DIR/react.lock
Return.
```

#### `critical` (HARD STOP, ≥90%) — Pause sequence

```
1. PAUSE LOCK adicional:
   Bash (single): [ -f "$SESSION_DIR/pause.lock" ] && echo BUSY || echo FREE
   Se BUSY: HARD STOP já em curso noutra invocação — return.
   Senão: criar pause.lock com PID.

2. TaskList → identificar subagents activos (status != completed).

3. SendMessage cooperativo a cada subagent activo:
   "PAUSA ASAP. Não inicies nova tarefa nem continues esta. Reporta idle.
    Escreve estado parcial a disco antes de parar. Retoma automática
    após reset 5h via SendMessage."

4. Polling TaskList a cada 10s (timeout 180s) para confirmar idle.
   Subagents que não confirmem em 180s: marcar "in-flight" no checkpoint.

5. Write checkpoint em $CHECKPOINT (criar dir se não existe):

   ---
   paused_at: <ISO UTC now>
   resume_at: <RES + 5min em ISO UTC>
   used_percentage_at_pause: <PCT>
   cron_id: <preenchido no passo 7>
   workflow_active: <inferir de TaskList + contexto>
   project_dir: <$CLAUDE_PROJECT_DIR>
   session_id: <$SESSION_ID>
   ---

   # Checkpoint — <timestamp local>

   ## Subagents activos ao pausar
   | ID | Nome | Status | Última SendMessage |
   |---|---|---|---|
   | ... | ... | paused/in-flight | ... |

   ## Contexto do workflow
   <Descrição livre baseada em TaskList + mensagens recentes>

6. Calcular resume_at = RES + 5min. Converter para cron 5-field LOCAL TZ.
   Se minute ∈ {0, 30}: +3min para evitar jitter.

7. CronCreate one-shot com prompt defensivo de retoma (ver secção abaixo).
   Tentar recurring=false; fallback recurring=true com self-CronDelete embutido.
   Edit checkpoint.md para preencher cron_id no frontmatter.

8. CLEANUP:
   rm $SESSION_DIR/soft-warn-sent.flag
   rm $SESSION_DIR/hard-warn-sent.flag
   rm $SESSION_DIR/pause.lock
   rm $SESSION_DIR/react.lock

9. Output final:
   "[session-guardian] 🛑 PAUSA ACTIVA.
    Plafond 5h ${PCT}%. Retoma agendada para <resume_at_local> (${MINS}min).
    Checkpoint: $CHECKPOINT
    MANTÉM O TERMINAL ABERTO (cron é session-scoped)."
```

### PASSO 5 — Append monitor.log

Sempre, em todos os paths excepto early-return defensivo:

```
Bash (single): echo "$(date -u +%FT%TZ) | react | zone=${ZONE} pct=${PCT} mins=${MINS} | <action_summary>" >> "$SESSION_DIR/monitor.log"
```

### PASSO 6 — Libertar lock

```
Bash (single): rm -f "$SESSION_DIR/react.lock"
```

## Prompt defensivo de retoma (HARD STOP)

Inserido no `prompt` do `CronCreate`:

```
A janela 5h do Claude Code foi renovada. Antes da pausa havia workflow em curso.

PROCEDIMENTO OBRIGATÓRIO (NÃO saltar passos):

1. Read TOOL: <CHECKPOINT_PATH>
2. Interpreta o checkpoint: workflow, subagents, última SendMessage, wave/fase.
3. Para cada subagent listado (paused ou in-flight):
   SendMessage(to=<name>, message="Pausa terminou. Estado antes: <resumo>.
   Retoma de onde ficaste. Confirma quando pronto.")
4. Aguarda confirmações (max 3min via TaskList polling).
5. SÓ então prosseguir o workflow original onde parou.

NÃO É ACEITÁVEL:
- "Vou verificar" sem actualmente Read TOOL no checkpoint.
- Plano sem executar passos 1-4.
- Compactar/resumir o trabalho — retoma no ponto EXACTO.
- Iniciar nova fase antes de subagents confirmarem.

Se checkpoint corrupto/suspeito: PARA e pergunta ao utilizador.
```

## Notas

- **One-shot**: skill termina sem ScheduleWakeup. Próxima invocação vem da próxima notification do monitor.
- **Lock files**: `react.lock` (durante toda a skill) e `pause.lock` (durante HARD STOP) protegem contra race conditions se duas notifications chegarem em rápida sucessão.
- **`hint` args vs rate-state**: args do monitor são úteis para context inicial mas a skill SEMPRE valida contra `rate-state.json`. Se houver discrepância, prevalece o ficheiro (mais recente).
- **Health pulses são idempotentes**: se a flag de zona já existe, skill apenas faz log. Não re-emite avisos.
- **Defensive cleanup em green/green-high**: cobre o edge case de reset sem HARD STOP. Em ≤30 min após reset, próximo health pulse trigger reactor → reactor vê zona green com flags antigas → limpa.
