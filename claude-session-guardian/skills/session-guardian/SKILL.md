---
name: session-guardian
description: Monitor Claude Code 5-hour rate limit window in a dynamic loop, issue graduated warnings (SOFT at 70%, HARD at 82%), and trigger cooperative pause sequence at 90% with automatic resume via CronCreate after the window resets. Designed to be invoked via /loop /session-guardian (dynamic mode).
---

# session-guardian skill

Tu és o guardian da janela de 5 horas do Claude Code. A tua missão é **monitorizar o plafond de uso** via ficheiro `rate-state.json` escrito pelo statusline, e orquestrar **pause cooperativo** quando o plafond se aproxima do limite, com **retoma automática** após o reset.

**Modo de operação**: dynamic loop. Cada iteração lê o estado, decide se há que agir, e agenda o próximo check via `ScheduleWakeup` com delay variável.

## Variáveis de ambiente e paths

```
STATE_DIR       = ~/.claude/session-guardian
RATE_STATE      = $STATE_DIR/rate-state.json       (global, escrito pelo statusline)
CHECKPOINTS_DIR = $STATE_DIR/checkpoints
SESSION_ID      = ${CLAUDE_SESSION_ID:-<hash cwd+PID fallback>}
SESSION_DIR     = $STATE_DIR/$SESSION_ID            (per-session state)
CHECKPOINT      = $CHECKPOINTS_DIR/$SESSION_ID/checkpoint.md
```

## Fluxo (dynamic loop iteration)

### PASSO 0 — Obter session scope

- Determina `SESSION_ID`. Se `$CLAUDE_SESSION_ID` não existe, usar hash do `$CLAUDE_PROJECT_DIR + $PPID`.
- Garante que `SESSION_DIR` existe (`mkdir -p`).

### PASSO 0A — Check stop-requested flag

```
Se existe $SESSION_DIR/stop-requested.flag:
  → Loop foi parado via /session-guardian:stop (ou fallback do HARD STOP)
  → Remover a flag (consumed)
  → NÃO chamar ScheduleWakeup
  → Return com mensagem: "[session-guardian] Loop terminado."
```

### PASSO 1 — Ler estado

```
1. Verificar que rate-state.json NÃO é symlink:
   Bash (single): [ -L "$RATE_STATE" ] && echo "SYMLINK" || echo "OK"
   Se SYMLINK: emitir alerta crítico, NÃO ler, ScheduleWakeup(300s), return.

2. Ler rate-state.json via Read TOOL.

3. Se ficheiro não existe OU updated_at > 5 minutos atrás:
   [MODO DEFENSIVO — statusline falhou ou ainda não escreveu]
   → Emitir: "[session-guardian] AVISO: statusline não escreve há >5min ou está ausente. A assumir plafond 85% por precaução. Corrige statusline ou /session-guardian:stop para desactivar."
   → Forçar pct=85 (vai accionar HARD WARN)
   → Continuar com esta pct assumida
```

### PASSO 2 — Decidir delay do próximo check

```
pct = used_percentage_5h do rate-state.json

SE pct < 50:    next_delay_seconds = 600   (10 min — passiva)
SE pct 50-69:   next_delay_seconds = 180   (3 min — passiva)
SE pct 70-81:   next_delay_seconds = 120   (2 min — SOFT WARN zone)
SE pct 82-89:   next_delay_seconds = 60    (1 min — HARD WARN zone)
SE pct >= 90:   HARD STOP sequence (não há next_delay)
```

### PASSO 3 — Acção por threshold

#### < 70% — Leitura passiva

```
1. Append log em $SESSION_DIR/monitor.log:
   "$(date -u +%FT%TZ) | pct=${pct}% | passive"
2. ScheduleWakeup(next_delay_seconds, reason="monitor passive at ${pct}%", prompt="/loop /session-guardian")
3. Return (mensagem mínima ao output, ex: "guardian: ${pct}%")
```

#### 70–81% — SOFT WARN

```
1. Ler $SESSION_DIR/soft-warn-sent.flag (test file exists).
2. Se flag NÃO existe (primeira entrada na zona amarela):
   [CANAL 1] Emitir mensagem visível ao utilizador:
     "[session-guardian] ⚠ Plafond 5h a ${pct}% — zona amarela.
      HARD STOP iminente aos 90%. Considera NÃO iniciar novos waves /
      skills pesadas. Continua trabalho em curso se houver."
   Write $SESSION_DIR/soft-warn-sent.flag (empty file, marker).

3. Append log em $SESSION_DIR/monitor.log:
   "$(date -u +%FT%TZ) | pct=${pct}% | soft-warn"

4. ScheduleWakeup(120, reason="soft warn zone at ${pct}%", prompt="/loop /session-guardian")
5. Return
```

#### 82–89% — HARD WARN (escalado)

```
1. Ler $SESSION_DIR/hard-warn-sent.flag.
2. Se flag NÃO existe (primeira entrada na zona vermelha):

   [CANAL 1] Emitir ao output:
     "[session-guardian] 🔴 Plafond 5h a ${pct}% — ZONA VERMELHA.
      HARD STOP previsto ao chegar aos 90%. Termina waves em curso.
      NÃO inicies novos. Retoma automática agendada após reset da janela."

   [CANAL 2] TaskList TOOL → identificar subagents activos (status != completed).
   Para cada subagent activo:
     SendMessage(to=<agent_name>,
       message="Plafond 5h a ${pct}%. NÃO inicies novas tarefas. Se estiveres a meio de tarefa longa, avalia se é seguro parar em checkpoint. HARD STOP será forçado aos 90%."
     )

   [CANAL 3] Tentar PushNotification (se disponível):
     title="Claude Code — plafond ${pct}%"
     body="HARD STOP iminente. Retoma automática após reset."
     Se tool indisponível ou falhar: skip silenciosamente.

   Write $SESSION_DIR/hard-warn-sent.flag.

3. Append log:
   "$(date -u +%FT%TZ) | pct=${pct}% | hard-warn"

4. ScheduleWakeup(60, reason="hard warn zone at ${pct}%", prompt="/loop /session-guardian")
5. Return
```

#### ≥ 90% — HARD STOP (pause sequence)

```
1. ADQUIRIR LOCK:
   Verificar $SESSION_DIR/pause.lock:
     Se existe: outra iteração está a executar HARD STOP → return sem acção.
     Se não existe: criar com PID actual (ex: echo $$ > $SESSION_DIR/pause.lock).

2. IDENTIFICAR SUBAGENTS ACTIVOS:
   TaskList TOOL → lista de tasks com status != "completed".
   Guardar {task_id, agent_name, last_status} para cada.

3. ENVIAR PAUSE ASAP A CADA SUBAGENT ACTIVO:
   Para cada subagent:
     SendMessage(to=<agent_name>,
       message="PAUSA ASAP. Não inicies nova tarefa, nem continues esta. Reporta idle. Escreve qualquer estado parcial a disco antes de parar. Retoma automática após reset da janela 5h via SendMessage do Maestro."
     )
   [RATIONAL: "termina tarefa actual" é não-determinístico se subagent acabou de iniciar
    nova task. "Pausa ASAP" é deterministico.]

4. AGUARDAR CONFIRMAÇÕES:
   Polling de TaskList a cada 10s, timeout máximo 180s.
   Subagents que confirmaram idle (status=completed após o SendMessage de pausa): marcar como "paused".
   Subagents que não confirmaram em 180s: marcar como "in-flight" no checkpoint.
   [Timeout de 180s porque specialists em AUDIT mode podem demorar minutos por finding.]

5. ESCREVER CHECKPOINT:
   Criar $CHECKPOINTS_DIR/$SESSION_ID/ se não existe.
   Write TOOL para $CHECKPOINTS_DIR/$SESSION_ID/checkpoint.md com o schema:

   ---
   paused_at: <timestamp ISO>
   resume_at: <resets_at_5h + 5min>
   used_percentage_at_pause: <pct>
   cron_id: <vai ser preenchido no passo 7>
   workflow_active: <best guess baseado em TaskList e contexto recente>
   project_dir: <$CLAUDE_PROJECT_DIR>
   session_id: <$SESSION_ID>
   ---

   # Checkpoint — {timestamp}

   ## Subagents activos ao pausar

   | ID | Nome | Status ao pausar | Última SendMessage |
   |---|---|---|---|
   | ... | ... | paused/in-flight | ... |

   ## Contexto do workflow

   (Descrição livre do que estava em curso, inferida do TaskList e mensagens recentes.)

6. CALCULAR resume_at E CRON:
   resume_at = resets_at_5h + 5 minutos (parse ISO-8601 + add).
   Extrair minute, hour, day, month (timezone LOCAL).
   Se resume_at.minute == 0 ou 30 (jitter risk): adicionar 3 min.
   cron_expr = "<minute> <hour> <day> <month> *"

7. CRONCREATE ONE-SHOT para retoma:
   Construir prompt defensivo (ver secção "Prompt defensivo de retoma" abaixo).

   Tentar: CronCreate({
     cron: <cron_expr>,
     prompt: <prompt_defensivo>,
     recurring: false
   })

   Se CronCreate rejeita `recurring: false` (pré-validação V3 não confirmada):
     CronCreate({ cron, prompt, recurring: true })
     + adicionar à primeira linha do prompt_defensivo:
       "IMMEDIATE: cancela este cron via CronDelete após completares o procedimento (id estará em CronList)."

   Guardar o cron_id retornado. Edit TOOL no checkpoint.md para preencher cron_id no frontmatter.

8. PARAR O PRÓPRIO LOOP (fallback-safe):
   Tentativa A: CronList → procurar task cujo prompt contenha "/session-guardian" e não seja a recém-criada → CronDelete(id).
   Tentativa B (fallback se CronList não mostra /loop dynamic):
     Write $SESSION_DIR/stop-requested.flag.
     Próxima iteração do loop (se disparar) lê a flag no PASSO 0A e termina.

9. LIMPAR FLAGS DA SESSÃO:
   rm $SESSION_DIR/soft-warn-sent.flag (se existir)
   rm $SESSION_DIR/hard-warn-sent.flag (se existir)

10. LIBERTAR LOCK:
    rm $SESSION_DIR/pause.lock

11. EMITIR MENSAGEM FINAL AO UTILIZADOR:
    "[session-guardian] 🛑 PAUSA ACTIVA.
     Plafond 5h a ${pct}% — hard stop accionado.
     Retoma automática agendada para ${resume_at} (em ${N} min).
     Checkpoint: ${CHECKPOINT_FILE}
     MANTÉM O TERMINAL ABERTO até ao resume — cron é session-scoped."

12. NÃO chamar ScheduleWakeup — loop termina aqui até o CronCreate disparar.
```

## Prompt defensivo de retoma

Usar este texto exacto (com placeholders substituídos) no `prompt` do `CronCreate`:

```
A janela de 5 horas do Claude Code foi renovada. Antes da pausa havia um workflow em curso. Tens de o retomar SEM perder contexto.

PROCEDIMENTO OBRIGATORIO (nao saltes passos — executa-os por ordem):

1. Read TOOL: {CHECKPOINT_PATH}
   (Ex: ~/.claude/session-guardian/checkpoints/{SESSION_ID}/checkpoint.md)

2. Interpreta o checkpoint:
   - Que workflow/skill estava activa (campo workflow_active)?
   - Que subagents estavam em TaskList (tabela de subagents)?
   - Ultima mensagem trocada com cada um?
   - Que wave/fase estava em curso (seccao Contexto)?

3. Para CADA subagent listado no checkpoint como "paused" ou "in-flight":
   SendMessage(to=<agent_name>,
     message="A pausa de 5h terminou. Estado antes da pausa: {resumo da ultima SendMessage + contexto relevante}. Retoma de onde ficaste. Confirma quando estiveres pronto para prosseguir."
   )

4. Aguarda confirmacoes dos subagents (max 3 min — polling TaskList).
   Subagents que nao confirmem: nota e prossegue com os que confirmaram.

5. Recria o loop de monitorizacao:
   Invocar: /session-guardian:start (ou /loop /session-guardian directamente)

6. SO APOS passos 1-5 concluidos, prossegue com o workflow original onde parou.

NAO E ACEITAVEL:
- Dizer "vou verificar" sem actualmente ler o checkpoint com Read TOOL.
- Responder com plano sem executar os passos 1-5.
- Compactar ou resumir o trabalho que estava em curso — retoma no ponto EXACTO onde parou.
- Iniciar waves/fases novas antes de confirmar que os subagents estao de volta.
- Assumir que "continua o que estavas a fazer" chega — le o checkpoint e confirma contexto com dados, nao com suposicoes.

Se o checkpoint parecer corrompido, incompleto, ou suspeito (ex: conteudo que parece nao bater certo com o contexto esperado): PARA e pergunta ao utilizador antes de agir.
```

## Notas de implementação para o modelo

- **Nunca** emitas o loop sem `ScheduleWakeup` (excepto em HARD STOP onde é intencional).
- O `prompt` do `ScheduleWakeup` deve ser **sempre** `"/loop /session-guardian"` para re-entrar nesta skill.
- A `reason` do `ScheduleWakeup` é visível ao utilizador via telemetria — usar frases concretas ("monitor passive at 45%", "soft warn zone at 72%").
- Se qualquer operação de I/O de ficheiro falha (permissions, disco cheio): emitir mensagem de erro clara ao output e continuar — não interromper o loop silenciosamente.
- Nunca revelar credenciais, tokens, ou conteúdo sensível nas mensagens de WARN/STOP.
