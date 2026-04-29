# claude-session-guardian

Monitor da janela de 5 horas do Claude Code (Max subscription) com pausa cooperativa automática e retoma agendada após o reset da janela.

## Arquitectura (v1.1.0+)

Background monitor + skill reactiva. Em vez de um `/loop` que paga 1 turn por iteração (~1pp/min), agora um shell script roda em background e o Claude só é chamado quando há sinal real.

```
┌────────────────────────────────┐
│ statusline                     │  Cada turn / refreshInterval=60s
│ (lê rate_limits, escreve JSON) │  Sem custo de tokens.
└──────────┬─────────────────────┘
           ↓ rate-state.json
┌────────────────────────────────┐
│ monitors/watch-rate-state.sh   │  Background process.
│ (Detector — shell, sem tokens) │  Polls cada 60s.
└──────────┬─────────────────────┘
           ↓ stdout (notification)
           │ Só em ZONE_UPGRADE ou
           │ HEALTHY (a cada 30 min)
┌──────────▼─────────────────────┐
│ Claude Code                    │  Recebe notification no chat,
│ → invoca /session-guardian:react│  invoca a skill react.
└──────────┬─────────────────────┘
           ↓
┌────────────────────────────────┐
│ skill react                    │  Decide acção (WARN, HARD STOP).
│ (tem acesso a tools)           │  Tem TaskList, SendMessage,
│                                │  CronCreate.
└────────────────────────────────┘
```

## O que faz

1. **Detector em background (zero tokens)** — `monitors/watch-rate-state.sh` poll a cada 60s. Notifica o Claude **só** em transições de zona (UPGRADE) ou em pulsos de saúde (a cada 30 min).
2. **Avisos graduados via reactor** — SOFT WARN aos 70%, HARD WARN aos 82% (com SendMessage a subagents activos + push notification).
3. **Pause cooperativo aos 90%** — reactor pede a todos os subagents para "Pausa ASAP e reporta idle", escreve checkpoint, agenda retoma via `CronCreate`.
4. **Retoma automática** — ao fim de `resets_at + 5min`, Cron dispara prompt defensivo que força o Claude a ler checkpoint e retomar.

## Quando usar

- Workflows longos multi-agent (ex: audits do `clickup-code-review`) onde perder a sessão a meio custa muito.
- Sessões onde tipicamente chegas ao limite de 5h sem perceber.
- Qualquer sessão onde queres ter certeza que o trabalho em curso não é abruptamente cortado quando a janela termina.

## Requisitos

- Claude Code CLI ≥ **2.1.121** (refreshInterval em statusline; plugin monitors disponíveis desde 2.1.105)
- Max subscription (Pro tem janela 5h mas o payload pode diferir — não testado)
- `jq` instalado (usado pelo statusline + monitor + setup)
- **Não suportado**: Bedrock, Vertex AI, Microsoft Foundry — Monitor tool indisponível nestes hosts. Fallback: `/loop /session-guardian` legacy (skill mantida)

## Instalação

### 1. Instalar o plugin

Via marketplace `joaoin0x-cc-plugins` (adicionado automaticamente se já instalaste outros plugins deste marketplace), ou manualmente via:

```
/plugin install claude-session-guardian@joaoin0x-cc-plugins
```

### 2. Correr setup (uma vez)

```
/session-guardian:setup
```

O setup:
- Descobre o path absoluto do statusline script
- Faz backup atómico do teu `settings.json` para `settings.json.pre-session-guardian`
- Actualiza `statusLine.command` para o script do plugin
- Cria `$CLAUDE_CONFIG_DIR/session-guardian/checkpoints/`
- Valida o JSON resultante (restaura backup se inválido)

### 3. Reload e nova sessão

```
/reload-plugins
```

Fecha o terminal actual e abre uma sessão nova. O monitor `rate-limit-watcher` arranca **automaticamente** (declarado no plugin manifest). Já não precisas de invocar `/session-guardian:start` — o background detector fica activo desde o startup.

Para confirmar que está a correr:
```
TaskList | grep rate-limit-watcher
```

## Uso

| Comando | O que faz |
|---|---|
| `/session-guardian:setup` | Configuração inicial (1 vez por instalação) |
| `/session-guardian:start` | Arranca o loop de monitorização manualmente |
| `/session-guardian:stop` | Pára o loop (com confirmação obrigatória — anti prompt-injection) |
| `/session-guardian:uninstall` | Reverte o setup; restaura `settings.json.pre-session-guardian` |

Durante uma sessão monitorizada, vês no statusline algo como:

```
Opus 4.7 · 5h 67% (reset 19:30) · 7d 23%
```

## Thresholds

| Uso | Acção |
|---|---|
| < 50% | Check a cada 10 min |
| 50–69% | Check a cada 3 min |
| **70–81%** | **SOFT WARN** (terminal) — não inicies novos waves |
| **82–89%** | **HARD WARN** (terminal + SendMessage a subagents + notificação) — escala de urgência |
| **≥ 90%** | **HARD STOP** — pause sequence + retoma agendada para `resets_at + 5min` |

## Durante a pausa

Quando o HARD STOP dispara:
1. Todos os subagents activos recebem `SendMessage` a pedir "Pausa ASAP"
2. O estado do workflow é persistido em `$CLAUDE_CONFIG_DIR/session-guardian/checkpoints/<session_id>/checkpoint.md`
3. Um cron one-shot é agendado para `resets_at + 5min`
4. **Manter o terminal aberto** — crons são session-scoped. Se fechares, a retoma não acontece.

Ao retomar, o prompt defensivo força o modelo a:
- Ler o checkpoint
- Re-enviar contexto aos subagents via `SendMessage`
- Recriar o loop de monitorização
- Continuar o workflow onde parou

## Trade-offs conhecidos

- **Terminal tem de ficar aberto durante a pausa** — limitação do CronCreate ser session-scoped.
- **Subagents com tasks longas podem não confirmar em 180s** — são marcados "in-flight" no checkpoint; retoma contacta-os na mesma.
- **Path do plugin é congelado no setup** — se o plugin for movido (upgrade para path diferente), o statusline quebra. Reparação: correr `/session-guardian:uninstall` seguido de `/session-guardian:setup`.
- **Statusline próprio** — não wrap do ccstatusline. Se usas ccstatusline, o setup sobrescreve. Uninstall restaura.
- **Edits interrompidos a meio** — se um subagent estava a meio de `Write`/`Edit` ao receber "Pausa ASAP", o ficheiro pode ficar em estado parcial. O prompt de pausa inclui "escreve estado parcial a disco antes de parar" como mitigação best-effort.

## Privacidade e segurança

- O `rate-state.json` contém apenas percentagens e timestamps — sem conteúdo sensível.
- O checkpoint.md contém nomes de subagents e descrição livre do workflow — pode conter nomes de ficheiros do teu projecto. É escrito em `$CLAUDE_CONFIG_DIR/session-guardian/` (fora do projecto) com permissões 0600.
- Stop skill exige confirmação explícita (`AskUserQuestion`) — defesa contra prompt injection.
- Audit log de paragens em `$CLAUDE_CONFIG_DIR/session-guardian/audit.log`.
- Statusline rejeita escritas se o path alvo for symlink.

## Desinstalar

```
/session-guardian:uninstall
```

Restaura `settings.json` a partir do backup. Opcionalmente apaga `$CLAUDE_CONFIG_DIR/session-guardian/` (checkpoints, logs). Não remove os ficheiros do plugin — para isso usa o menu `/plugin`.

## Licença

MIT — ver LICENSE.

## Autor

joaoin0x — joaodavidantunes@gmail.com
