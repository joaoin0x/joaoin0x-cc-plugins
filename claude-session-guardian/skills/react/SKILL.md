---
name: react
description: Reactor invoked when the rate-limit-watcher monitor emits a notification. Decides action by zone (5h) or weekly status (7d) and executes atomically. v1.1.3 — pre-emptive resume cron is created on the FIRST upgrade (yellow) so the session resumes after reset even if HARD STOP is never reached. RESET_DETECTED cancels the cron when the user managed the rate limit naturally. HARD STOP keeps CronCreate-first ordering as insurance.
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
RESUME_CRON_FILE    = $SESSION_DIR/resume-cron.json   (pre-emptive cron tracking)
REACTOR_STATUS_FILE = $STATE_DIR/.reactor-status      (consecutive error count)
```

## Princípios fundamentais (v1.1.3)

1. **Pre-emptive resume cron no 1º disparo (yellow)**: a falha de FSL (perda de 9h) mostrou que confiar no critical para criar cron é miopia — se o utilizador adormece em yellow/red, plafond fica preso até alguém intervir manualmente. Solução: agendar retoma ASSIM QUE há sinal de risco. Idempotente: red/critical validam (e recriam se `resets_at` mudou) em vez de duplicar.
2. **Cron preventivo é cancelado em RESET_DETECTED**: se a janela renovou naturalmente (utilizador geriu sem HARD STOP), o cron deixa de fazer sentido. Cancela-se para evitar disparar em sessão activa.
3. **CronCreate FIRST em HARD STOP**: na zona crítica, mesmo que cron preventivo já exista, validar/recriar antes de SendMessage e checkpoint. Garante que falhas posteriores não comprometem retoma.
4. **Sem polling de TaskList**: 1 single check, marcar tudo o resto como "in-flight". Polling causou stream-idle timeout de 15min no incidente de 30 Apr.
5. **Operações em paralelo onde possível**: SendMessage a múltiplos subagents em parallel tool calls (1 turn).
6. **Error tracking**: ao falhar (qualquer step), incrementar `$REACTOR_STATUS_FILE`. Ao succeeder fully, escrever 0.
7. **Single Bash em paths leves**: green / RESET_DETECTED / weekly não devem usar 7+ Bash calls. Consolidar em 1 single Bash quando possível.
8. **Cadence adaptive vem do detector**: o reactor NÃO decide quando voltar a correr. Próxima invocação vem da próxima notification do detector (que poll com cadence apropriada à zona actual).

## Procedimento

### Helper conceptual — `ensure_resume_cron(zone, pct, resets_at)`

**Idempotente.** Garante que existe um cron de retoma agendado para `resets_at + 5min`. Se já existe e `resets_at` não mudou, retorna `cron_id` existente. Se mudou (sliding window), apaga e recria. Se não existe, cria.

```
Bash (single, validation):
  RESETS="<resets_at_iso>"
  RESUME_EPOCH=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "${RESETS%Z}" "+%s") + 300
  NOW=$(date -u +%s)
  if [ $((RESUME_EPOCH - NOW)) -le 60 ]; then echo "TOO_LATE"; exit; fi

Read TOOL: $RESUME_CRON_FILE  (se existe)
  Se existe:
    STORED_RESETS = .resets_at_5h
    STORED_CRON_ID = .cron_id
    Se STORED_RESETS == RESETS:
      // Cron existente ainda válido — retornar STORED_CRON_ID, não fazer nada.
      RETURN ("EXISTS", STORED_CRON_ID)
    Senão:
      // resets_at mudou (sliding window) — invalidar antes de recriar.
      CronDelete TOOL: task_id=STORED_CRON_ID  (best-effort, ignora erro)

Bash (single, build cron expr):
  Em local TZ, derivar de RESUME_EPOCH:
    MINUTE=$(date -r $RESUME_EPOCH +%M)
    HOUR=$(date -r $RESUME_EPOCH +%H)
    DAY=$(date -r $RESUME_EPOCH +%d)
    MONTH=$(date -r $RESUME_EPOCH +%m)
  Se MINUTE ∈ {00, 30}: MINUTE=$((MINUTE + 3))  (jitter avoidance)
  cron_expr = "$MINUTE $HOUR $DAY $MONTH *"
  RESUME_AT_LOCAL = $(date -r $RESUME_EPOCH "+%Y-%m-%d %H:%M")

Construir PROMPT_RESUME (ver secção "Prompt de retoma" abaixo) — interpolar literais:
  - <CHECKPOINT_PATH>     → $STATE_DIR/checkpoints/$SESSION_ID/checkpoint.md
  - <RESUME_AT_LOCAL>     → derivado acima
  - <SESSION_ID>          → $SESSION_ID
  - <PROJECT_DIR>         → $CLAUDE_PROJECT_DIR

CronCreate TOOL:
  cron: <cron_expr>
  prompt: <PROMPT_RESUME>
  recurring: false
  Se rejeita recurring=false: usar recurring=true + prefixar self-CronDelete.

Guardar CRON_ID retornado.

Write TOOL: $RESUME_CRON_FILE
  Conteúdo (JSON):
    {
      "cron_id": "<CRON_ID>",
      "resets_at_5h": "<RESETS>",
      "resume_at_local": "<RESUME_AT_LOCAL>",
      "trigger_zone": "<zone>",
      "trigger_pct": <pct>,
      "created_at": "<ISO UTC now>"
    }

RETURN ("CREATED", CRON_ID)
```

**Erro paths**:
- `TOO_LATE`: reset já passou ou < 60s — não criar cron, increment error, retornar `("ABORT_TOO_LATE", null)`.
- `CronCreate rejeita`: increment error, retornar `("ABORT_CRON_FAIL", null)`.

### Helper conceptual — `cancel_resume_cron()`

Chamado em RESET_DETECTED (cleanup pós-reset natural) e em stop manual.

```
Read TOOL: $RESUME_CRON_FILE
  Se ausente: return (silencioso — não havia cron preventivo).
  Senão:
    STORED_CRON_ID = .cron_id

CronDelete TOOL: task_id=STORED_CRON_ID  (best-effort)

Bash (single): rm -f "$RESUME_CRON_FILE"

RETURN STORED_CRON_ID  (para log)
```

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

#### `yellow` (SOFT WARN, 65-74%) — Aviso + cron preventivo (PRIMEIRO disparo)

**v1.1.3**: este é o ponto de entrada da segurança. O cron de retoma é agendado AQUI, no primeiro sinal de risco, não só em critical. Lição da incidência FSL (perda de 9h porque sessão parou em yellow sem cron).

```
Se NÃO existe $SESSION_DIR/soft-warn-sent.flag:
  Output: "[session-guardian] ⚠ Plafond 5h a ${PCT}% — zona amarela.
           ${MINS} min até reset. HARD STOP automático aos 85%.
           Considera não iniciar novos waves / skills pesadas."

  // Cron preventivo — insurance contra dormência
  Invocar ensure_resume_cron(zone=yellow, pct=$PCT, resets_at=$RESETS)
    Se ("CREATED", CRON_ID): output "[session-guardian] Retoma preventiva agendada: cron id=${CRON_ID} dispara <RESUME_AT_LOCAL>."
    Se ("EXISTS", CRON_ID): (raro neste path — cron poderia ter sobrevivido a stop+start) silent.
    Se ("ABORT_TOO_LATE", _): output "[session-guardian] Reset iminente (<60s) — sem cron preventivo, retoma natural será suficiente."
    Se ("ABORT_CRON_FAIL", _): output "[session-guardian] ⚠ Falha a criar cron preventivo — investiga via CronList. Retoma manual será necessária se a sessão dormir."

  Bash (single): touch "$SESSION_DIR/soft-warn-sent.flag"

(Se flag existe — disparo repetido na mesma zona — silent. Cron já existe.)

Reset error count.
rm react.lock. Return.
```

#### `red` (HARD WARN, 75-84%) — Aviso urgente + revalidar cron

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

  // Revalidar cron preventivo (caso resets_at tenha mudado por sliding window,
  // ou se yellow foi saltado ex: pct subiu rápido de 60→78 entre polls)
  Invocar ensure_resume_cron(zone=red, pct=$PCT, resets_at=$RESETS)
    Se ("CREATED", CRON_ID): output "[session-guardian] Retoma preventiva agendada (red): cron id=${CRON_ID} dispara <RESUME_AT_LOCAL>."
    Se ("EXISTS", _): silent — cron de yellow ainda válido.
    Se ABORT: output erro como em yellow.

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

4.2 + 4.3 CRONCREATE FIRST via ensure_resume_cron (insurance — retoma garantida)

  Invocar ensure_resume_cron(zone=critical, pct=$PCT, resets_at=$RESETS)

  Casos:
    ("EXISTS", CRON_ID): cron preventivo de yellow/red ainda válido — usar.
    ("CREATED", CRON_ID): novo cron criado (yellow foi saltado, ou cron foi
                          cancelado entretanto, ou resets_at sliding window).
    ("ABORT_TOO_LATE", _):
      Output: "[session-guardian] HARD STOP abortado — reset_at já passou (<60s).
               Cleanup defensivo + retoma natural será suficiente."
      Bash (parallel): rm -f $SESSION_DIR/{pause,react}.lock; rm -f $SESSION_DIR/{soft,hard}-warn-sent.flag
      Increment error (PASSO 7).
      Return.
    ("ABORT_CRON_FAIL", _):
      Output: "[session-guardian] ⚠ HARD STOP a prosseguir SEM cron de retoma —
               CronCreate falhou. Retoma manual obrigatória após reset. Investiga via CronList."
      // CRÍTICO: prosseguir mesmo assim — checkpoint + SendMessage ainda têm valor.

  Guardar CRON_ID retornado (pode ser null se ABORT_CRON_FAIL).

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

  // NOTA: NÃO apagar $RESUME_CRON_FILE aqui — cron continua agendado e o
  // ficheiro é a fonte de verdade para identificá-lo. Será limpo no PASSO 4-RESET
  // (quando a janela renovar) ou pelo prompt de retoma (que apaga o ficheiro
  // após retoma confirmada).

  Output:
    "[session-guardian] 🛑 PAUSA ACTIVA.
     Plafond 5h ${PCT}% — HARD STOP accionado.
     Cron de retoma: id=${CRON_ID}, dispara <resume_at_local>.
     Checkpoint: $CHECKPOINT
     SendMessages emitidas: <N> subagents alertados.
     MANTÉM O TERMINAL ABERTO (cron é session-scoped)."
```

### PASSO 4-RESET — Cleanup pós-reset (NOVO v1.1.2, expandido v1.1.3)

Disparado pelo detector quando a zona transita de active (yellow/red/critical) para quiet (green/green-high). Substitui o "defensive cleanup via health pulse" da v1.1.0/1.1.1.

**v1.1.3**: também cancela o cron preventivo (`resume-cron.json`) — se a janela renovou naturalmente, o utilizador geriu sem HARD STOP e o cron deixa de fazer sentido (evita disparar em sessão activa).

```
Cancelar cron preventivo:
  Invocar cancel_resume_cron()
    Se retornou CRON_ID: HAD_CRON=1, registar para output.
    Senão: HAD_CRON=0 (não havia — caso comum se HARD STOP já cancelou ou se nunca chegou a yellow).

Single Bash consolidado (1 call, não múltiplos):
  HAD_FLAGS=0
  if [ -f "$SESSION_DIR/soft-warn-sent.flag" ]; then HAD_FLAGS=1; rm -f "$SESSION_DIR/soft-warn-sent.flag"; fi
  if [ -f "$SESSION_DIR/hard-warn-sent.flag" ]; then HAD_FLAGS=1; rm -f "$SESSION_DIR/hard-warn-sent.flag"; fi
  rm -f "$SESSION_DIR/react.lock"
  echo "0" > "$REACTOR_STATUS_FILE"
  echo "$(date -u +%FT%TZ) | react | reset-detected | from=<prev> to=${ZONE} pct=${PCT} | flags_cleaned=${HAD_FLAGS} | cron_cancelled=${HAD_CRON}" >> "$SESSION_DIR/monitor.log"

Output (consolidado):
  Se HAD_FLAGS=1 ou HAD_CRON=1:
    Output: "[session-guardian] ✓ Reset detectado (pct=${PCT}). Zona ${ZONE}.
             Flags limpas: ${HAD_FLAGS}. Cron preventivo cancelado: ${HAD_CRON} (${CRON_ID se aplicável})."
  Senão:
    (silent — caso comum quando HARD STOP / stop manual já tinham limpado tudo)

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

## Prompt de retoma (interpolado em CronCreate, suporta ambos os caminhos)

Inserido literal no `prompt` do CronCreate. Funciona tanto para retoma de HARD STOP (checkpoint existe) como para retoma preventiva de yellow/red (checkpoint pode não existir):

```
A janela 5h do Claude Code foi renovada às <RESUME_AT_LOCAL>.
Foi agendada retoma automatica pelo session-guardian (sessao <SESSION_ID>).

PROCEDIMENTO OBRIGATORIO (NAO saltar passos):

PASSO 1 — Verificar se existe checkpoint (HARD STOP ocorreu):
  Bash: test -f "<CHECKPOINT_PATH>" && echo HARD_STOP || echo PRE_EMPTIVE

PASSO 2A — SE checkpoint EXISTE (caminho HARD STOP):
  1. Read TOOL: <CHECKPOINT_PATH>
  2. Interpreta o checkpoint: workflow, subagents, ultima SendMessage, wave/fase.
  3. Para cada subagent listado (paused ou in-flight):
     SendMessage(to=<name>, message="Pausa terminou. Estado antes: <resumo>.
     Retoma de onde ficaste. Confirma quando pronto.")
  4. Aguarda confirmacoes de subagents (max 3 min via TaskList — ou prossegue
     com os que confirmaram).
  5. SO entao prosseguir o workflow original onde parou.
  6. Apos retoma confirmada: rm -f "<CHECKPOINT_PATH>"

PASSO 2B — SE checkpoint NAO EXISTE (caminho PRE-EMPTIVE de yellow/red):
  Cenario: o session-guardian agendou cron de seguranca quando o plafond
  entrou em zona de risco, mas a sessao nao chegou a ser pausada (HARD STOP
  nunca disparou). A sessao pode estar dormente desde entao.

  1. TaskList TOOL — ha subagents activos?
     SE SIM (algum subagent em "running" ou "blocked"):
       Para cada subagent: SendMessage(to=<name>, message="Plafond 5h foi
       renovado. Se aguardavas por capacidade, retoma trabalho. Reporta
       estado actual.")
       Aguarda confirmacao (max 2 min).

  2. Inspeccionar trabalho recente (sinais de workflow inacabado):
     Bash: cd "<PROJECT_DIR>" && git status --short 2>/dev/null
     Bash: cd "<PROJECT_DIR>" && git log --since="6 hours ago" --oneline 2>/dev/null
     Bash: ls -lt "<PROJECT_DIR>" 2>/dev/null | head -20

  3. SE ha trabalho em curso evidente (alteracoes uncommitted, commits recentes,
     ficheiros modificados nas ultimas horas):
       Output: "[session-guardian:retoma-preventiva] Plafond renovado. Trabalho
       em curso detectado: <resumo>. Continua de onde ficaste ou pergunta ao
       utilizador qual a prioridade."

     SE NAO ha sinal de trabalho activo:
       Output: "[session-guardian:retoma-preventiva] Plafond renovado mas sem
       sinal de trabalho activo. Aguardo indicacao."

  4. Limpar ficheiro de tracking: Bash: rm -f "<RESUME_CRON_FILE>"

REGRAS GERAIS (ambos caminhos):
- "Vou verificar" sem actually Read TOOL no checkpoint NAO E ACEITAVEL.
- Compactar/resumir trabalho NAO E ACEITAVEL — retoma no ponto EXACTO.
- Iniciar nova fase antes de subagents confirmarem NAO E ACEITAVEL.
- Se checkpoint corrupto/suspeito: PARA e pergunta ao utilizador.
- Se contexto incoerente (workflow refere ficheiros inexistentes, etc.):
  PARA e pergunta ao utilizador.
```

## Notas de implementação

- **Pre-emptive cron no 1º disparo (yellow)** é a defesa principal contra dormência. A falha de FSL (perda de 9h) ocorreu porque o cron só era criado em critical, e a sessão parou em yellow.
- **CronCreate primeiro em HARD STOP é não-negociável**: foi a falha de 30 Apr. Mesmo que cron preventivo já exista, validar via ensure_resume_cron antes de SendMessage e checkpoint.
- **Sem polling**: o incidente de 30 Apr mostrou que 15 min de polling matam a sessão por stream-idle. 1 single TaskList check + assume rest as in-flight é suficiente.
- **PARALLEL tool calls**: SendMessages a múltiplos subagents devem ser parallel (single message com múltiplos tool_use blocks). Reduz latência de N turns para 1.
- **Lock files com PID**: react.lock e pause.lock contêm PID. Em recuperação de crashes futuros, podemos validar PID vs `kill -0` para detectar locks stale.
- **Validation `RESUME_EPOCH <= now+60s`**: cobre o caso onde reset já passou (sliding window) — abort criação de cron em vez de o agendar no passado.
- **Idempotência de ensure_resume_cron**: yellow cria, red e critical validam. Se `resets_at` mudou (sliding window) entre disparos, recria. Evita crons duplicados ou desactualizados.
- **resume-cron.json é per-session** (`$SESSION_DIR/resume-cron.json`) — múltiplas sessões em paralelo têm crons independentes, cada um cancelado pelo seu próprio RESET_DETECTED.
