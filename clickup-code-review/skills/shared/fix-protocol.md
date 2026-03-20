# Fix Protocol (Shared — v5.3.0)

Esqueleto do protocolo FIX — lido pelos specialists no arranque do mode FIX.

**NOTA:** Este é o esqueleto condensado. A referência completa (com serial queue strategy, comment detection, commit format, wave conflicts, branch strategy, e exemplos detalhados) está em `skills/fix/references/fix-protocol.md`. Os specialists seguem ESTE esqueleto; o Maestro lê a referência completa via SKILL.md.

**Audiência:** Specialists (implementam). O DA segue o seu próprio protocolo (MODE: CODE-REVIEW no agent .md). O Maestro segue o SKILL.md.

## PASSO Skeleton

```
PASSO 1: RECEBER CONTEXTO
  - Ler ficheiro .md local do ticket (descricao + secção Planeamento)
  - Ler plano aprovado (abordagem, ficheiros, passos)
  - Se sub-seccao ##### Correcção Sugerida (Actualizado após Planeamento) existe:
    → usa ESTA versao (tem precedencia sobre a original)
  - Se novos comentarios: adaptar conforme instrucao do Maestro

PASSO 2: LER FICHEIROS ALVO
  - Ler TODOS os ficheiros listados no plano
  - Verificar que o plano ainda se aplica (codigo pode ter mudado)
  - Se desactualizado → reportar ao Maestro antes de prosseguir

PASSO 3: IMPLEMENTAR FIX
  - Seguir passos do plano EXACTAMENTE
  - Modificar APENAS ficheiros listados no plano
  - Se precisar modificar ficheiro nao listado → pedir permissao ao Maestro
  - [DOMAIN-SPECIFIC focus — ver agent .md]
  - Progresso per-file: append "{timestamp} | IMPLEMENTING | ticket {id} | MODIFIED | {filepath}"

PASSO 4: SELF-VALIDATE
  - Re-ler TODOS os ficheiros modificados
  - Verificar sintaxe (nenhum erro obvio)
  - Verificar conventions do projecto (CLAUDE.md)
  - Verificar que nao introduziu novos problemas

PASSO 5: REPORTAR FICHEIROS MODIFICADOS (NÃO fazer git add)
  - Listar TODOS os ficheiros modificados/criados
  - Capturar diff: git diff <ficheiros> (unstaged diff, NÃO staged)
  - Se diff > 200 linhas: salvar em ficheiro separado
  - Append progress: "{timestamp} | MODIFIED | ticket {id} | {N} files: {lista}"
  - PROIBIDO: git add, git stage, ou qualquer operação git de staging
    O Maestro é o ÚNICO que faz git add + git commit (controla staging area)

PASSO 6: ENVIAR AO DA (CODE-REVIEW)
  - SendMessage ao DA com template:
    ## CODE REVIEW — {Ticket Title}
    **Ticket ID:** {id}
    **Area:** {area}
    ### Original Finding
    **Problema:** {texto completo}
    **Impacto:** {texto completo}
    ### Planned Fix
    {passos do plano}
    ### Files Modified
    {lista com descricao breve}
    ### Diff
    {diff completo ou stats+sample+path se >200 linhas}

PASSO 7: ESPERAR VERDICT DO DA
  - APPROVED → report final ao Maestro com LISTA DE FICHEIROS (NUNCA commitar, NUNCA fazer git add)
    → report inclui: DA verdict + reasoning + lista exacta de ficheiros modificados
  - REQUEST-CHANGES → corrigir, capturar novo diff, enviar ao DA (max 2 rounds)
    → report inclui: cada round de feedback + correcção aplicada
  - Apos 2 rejeições → escalar ao Maestro com historico COMPLETO
```

## Specialist↔DA Direct Flow

O specialist envia diff DIRECTAMENTE ao DA. O Maestro NAO esta no meio.
Fluxo: Specialist stages → sends diff to DA → DA reviews → verdict to Specialist
Specialist reporta resultado final ao Maestro → Maestro commita.

## Evidence Gates (por transicao de status)

| Transição | Evidência Requerida |
|-----------|-------------------|
| ready for dev → in progress | .md local existe (MINIMO) + #### Planeamento (IDEAL) |
| in progress → code review | Diff capturado + diff enviado ao DA |
| code review → in progress | DA REQUEST-CHANGES (specialist corrige) |
| code review → testing | DA APPROVED + Commit SHA + #### Decisões Fix |
| testing → deploy to staging | DA QA-APPROVED |

## Max 2 Revision Rounds

Specialist↔DA: max 2 rounds de REQUEST-CHANGES.
Apos 2 rejeições → specialist escala ao Maestro com historico COMPLETO.

## Rollback

Se fix causa regressão: `git revert <commit>`, max 2 retries por ticket.

## Rules

- SEGUIR O PLANO — implementar o que foi planeado
- NUNCA git add, NUNCA git commit — só o Maestro faz staging e commit
  O specialist implementa (Edit/Write) e reporta a lista de ficheiros ao Maestro
- UM TICKET DE CADA VEZ
- FICAR NO SCOPE — so modificar ficheiros do plano
- NAO correr comandos destrutivos
