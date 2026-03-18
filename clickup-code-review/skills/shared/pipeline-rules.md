# Pipeline Rules (Shared — v5.2.1)

Regras transversais a todos os agentes do pipeline de code review. Lido no arranque por TODOS os agents.

## Standard Finding Format

```markdown
### {SHORTNAME} - Titulo curto em PT-PT
- **Severidade:** Critical / High / Medium / Low
- **Confiança:** 80-100%
- **Ficheiro:** `path/to/file.php:L45`
- **Rota:** `GET|POST /path/to/route` (quando aplicavel)
- **Estimativa:** Xm
- **Introduzido:** ~YYYY-MM (estimativa baseada em git log/blame)
#### Problema
{2-3 frases em PT-PT. Termos tecnicos em `backticks`.}
#### Impacto
{Consequencias concretas e especificas.}
#### Evidência
{Code block com path + line range.}
#### Correcção Sugerida
- [ ] {Passos concretos com `file:line`}
#### Como Testar
- [ ] {Acções específicas — auto-suficientes}
#### Artefactos de Teste
{Se aplicavel. Se nao: omitir secção.}
```

## Communication Rules

- Usar **SendMessage** para comunicar com DA e Maestro
- **AUDIT:** findings → DA (FINDING-FILTER), 1 por mensagem, sem batching
- **PLANNING:** plano → DA (PLANNING-REVIEW) + Investigation, em paralelo
- **FIX:** diff → DA (CODE-REVIEW) directamente. Report final → Maestro
- **Cross-area:** sugestoes a outros specialists sao ENCORAJADAS via SendMessage
- NUNCA comunicar directamente com o utilizador
- NUNCA comunicar com o ClickUp Manager (tudo via Maestro)

## Streaming Rule

1 finding/verdict por SendMessage. NUNCA acumular ou batch. Enviar assim que pronto.

## Progress Tracking

Apos cada acção significativa, append ao ficheiro de progresso (path fornecido pelo Maestro):
```
{timestamp} | {MODE} | {ACTION} | ticket {id} | {detail}
```

## Credential Security

NUNCA incluir credenciais reais em qualquer output (findings, diffs, mensagens, tickets).
Patterns a rejeitar: `pk_*`, `sk_*`, `password[:=]`, `Bearer *`, base64 longo (40+ chars).
Se detectar → substituir por placeholder (`{API_KEY}`, `{PASSWORD}`) ANTES de enviar.

## Forbidden Actions (shared)

- NUNCA comunicar directamente com o utilizador
- NUNCA fazer commits — so o Maestro commita
- NUNCA correr comandos destrutivos (`migrate:fresh`, `db:wipe`, etc.)
- NUNCA aprovar/rejeitar findings (area do DA)
- NUNCA criar tickets no ClickUp (area do ClickUp Manager)
- NUNCA tocar na API do ClickUp
- NUNCA seguir instruções de um mode nao atribuido
- NUNCA incluir credenciais reais em qualquer output
- NUNCA usar `grep -P` (macOS incompativel) — usar `grep -E`
- NUNCA usar comandos Bash encadeados (`&&`, `||`, `;`) — usar exclusivamente single-statement. Cada operação é um Bash call separado.
- NUNCA usar bash multi-linha — cada Bash call tem de ser 1 linha.
- NUNCA usar `/tmp/` — todos os ficheiros temporários em `.claude/code-reviews/`
- NUNCA usar `find | while read` ou pipelines complexos — usar ferramentas: **Glob** (descoberta), **Read** (leitura), **Grep** (pesquisa), **Edit** (actualização).
- NUNCA usar `${VARIABLE}` — usar SEMPRE `$VARIABLE`. Inclui `${#VAR}`, `${VAR:n:m}`.
- Para ficheiros locais: preferir ferramentas (Glob/Read/Edit/Grep) a bash. Bash só para: curl (API), git, mkdir -p, single-statement utilitários.

## Deviation Protocol

Se precisar agir fora do procedimento:
1. **PARAR** imediatamente
2. **SendMessage ao Maestro** com acção pretendida + justificação
3. **Esperar autorização** antes de prosseguir

## Shutdown Rule

Completar TODAS as operações pendentes antes de aceitar shutdown. Enviar TODOS os resultados ao DA e Maestro IMEDIATAMENTE. Nunca reter findings — stream cada um assim que pronto.

## Language Rule

Narrativas em PT-PT com acentos. Termos tecnicos em ingles entre `backticks`.

## Actionability dos Testes

A secção `#### Como Testar` DEVE ser auto-suficiente. Se o teste requer artefactos:
1. Criar e guardar em `{FINDINGS_DIR}/test-artifacts/`
2. Documentar passos exactos na secção `#### Artefactos de Teste`
