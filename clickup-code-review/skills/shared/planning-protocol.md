# Planning Protocol (Shared — v5.2.9)

Esqueleto do protocolo PLANNING. Lido pelos specialists no arranque do mode PLANNING.

**Audiência:** O PASSO Skeleton é seguido pelos **specialists** (propõem planos). O DA segue o seu próprio protocolo (MODE: PLANNING-REVIEW no agent .md). O Investigation segue Papel 1/2 no agent .md. A secção Triangle Validation descreve como os 3 interagem.

## PASSO Skeleton

```
PASSO 1: RECEBER TICKET
  - Ler ficheiro .md local do ticket (Problema, Impacto, Evidência, Correcção Sugerida)
  - Ler comentarios recentes (se fornecidos pelo Maestro)

PASSO 2: VALIDAR FINDING
  - Re-ler ficheiros referenciados com olhos frescos
  - Verificar se o problema ainda existe (pode ter sido corrigido)
  - Re-avaliar severidade ao contexto do projecto
  - Estimar data de introdução: git log/blame
  - Se invalido → reportar INVALID ao DA e Investigation
  - Se parcialmente válido → reportar PARTIAL (ajustar scope/severidade, continuar plano)
  - Edge case: finding parcialmente válido — problema existe mas difere do descrito

PASSO 3: PLANEAR FIX (2 ABORDAGENS)
  - Abordagem A: {descrição, ficheiros, estimativa, pros/cons}
  - Abordagem B: {alternativa, ficheiros, estimativa, pros/cons}
  - Recomendar uma com justificação
  - Identificar ficheiros exactos (path:line)
  - Definir estrategia QA (unit/e2e/both/none)
  - [DOMAIN-SPECIFIC focus — ver agent .md]

PASSO 4: IDENTIFICAR DEPENDENCIAS
  - Depende de outro ticket? (e.g., migration antes de code fix)
  - Outro ticket depende deste?
  - Ficheiros em comum? (potencial conflito)

PASSO 5A: ENVIAR PLANO AO DA + INVESTIGATION
  - Append progress: "{timestamp} | PLANNING | ticket {id} | PLAN_SUBMITTED"
  - SendMessage ao DA (PLANNING-REVIEW) + Investigation (em paralelo)
  - Formato: Ticket ID, Finding válido, Severidade re-avaliada, Abordagem A/B,
    Ficheiros, Dependências, Estimativa, QA
  - Esperar feedback do DA E Investigation
  - Se NEEDS-CHANGE: revisar e re-enviar (max 2 rounds)
  - Se INVALID: escalar ao Maestro para fechar (Maestro instrui CU Manager)

PASSO 5B: REPORTAR RESULTADO AO MAESTRO
  - Só após consensus (DA VALID + Investigation VALID)
  - Report ao Maestro DEVE incluir DA + Investigation verdicts + reasoning
  - Formato: Ticket ID, verdict final, abordagem aprovada, ficheiros, wave, estimativa
```

## Triangle Validation

Specialist + DA + Investigation validam cada plano:
- **Specialist:** propoe 2 abordagens com trade-offs
- **DA (PLANNING-REVIEW):** desafia a abordagem, verifica qualidade
- **Investigation:** re-le codigo, valida fundamentacao, avalia impacto cross-area

Consensus: DA VALID + Investigation VALID → plano aprovado.
Max 2 rounds NEEDS-CHANGE. Apos 2 → escalar ao Maestro.

## Verdict Types

| Verdict | Significado | Acção |
|---------|-------------|-------|
| **VALID** | Finding confirmado, plano solido | Prosseguir |
| **INVALID** | Falso positivo | Fechar ticket |
| **PARTIAL** | Existe mas difere do descrito | Ajustar scope |
| **NEEDS-CHANGE** | Finding valido, abordagem precisa revisao | Specialist revisa (max 2) |

## Template `#### Planeamento`

```markdown
#### Planeamento
- **Agente:** {specialist-name}
- **Abordagem:** {A/B} — {descrição breve}
- **Abordagem {B/A} (rejeitada):** {razao breve}
- **QA:** {unit/e2e/both/none}
- **Ficheiros:** {lista}
- **Dependências:** {lista ou 'nenhuma'}
- **Wave:** {N}
- **Estimativa:** {Xm} (ver escala abaixo)

##### Correcção Sugerida (Actualizado após Planeamento)
{Versao refinada — tem PRECEDENCIA sobre a original}

##### Como Testar (Actualizado após Planeamento)
{Versao refinada — tem PRECEDENCIA sobre a original}
```

### Cálculo de Estimativas (instruções internas — NÃO incluir no ticket)

A estimativa é o tempo TOTAL do ciclo de vida do ticket, não apenas codificação.
O ticket mostra APENAS o valor final (ex: `**Estimativa:** 35m`). A decomposição abaixo é interna.

**Componentes FIXAS (overhead humano — iguais para TODOS os tickets, não variam):**

| Componente | Tempo |
|------------|-------|
| Abertura de Issue + Merge Request via UI | 3m |
| Terminal: pull, fetch, checkout branch novo | 2m |
| Code review visual (diff no MR antes de merge) | 5m |
| Testes em browser (verificação manual pós-deploy) | 5m |
| Commits, push, resolver merge request | 3m |
| **Subtotal fixo** | **18m** |

**Componente VARIÁVEL (estimada pelo agent — depende do ticket concreto):**

O agent estima livremente o tempo de implementação + validação/testes com base nos
ficheiros que identificou, a lógica envolvida, e as dependências. Não há categorias
fixas — cada ticket é diferente.

IMPORTANTE: A implementação é feita por um HUMANO assistido pelo Claude Code, não pelo
Claude sozinho. O humano lê o código, toma decisões, revê sugestões, e interage com o
Claude durante o processo. Estimar tempo de HUMANO + CLAUDE a trabalhar juntos, não
tempo de execução automática.

**Cálculo final (OBRIGATÓRIO):**

```
Estimativa = arredondar_15m( (Fixo 18m + Variável) × 1.10 )
```

1. Estimar tempo variável (implementação + validação) com base no código real
2. Somar 18m fixos (overhead humano)
3. Aplicar margem de 10%
4. Arredondar para cima ao múltiplo de 15m mais próximo

**Exemplos:**
- Fix de 1 linha, validação rápida: variável ~10m → (18+10)×1.10 = 30.8 → **30m**
- Corrigir query + adicionar validação: variável ~20m → (18+20)×1.10 = 41.8 → **45m**
- Refactoring de 3 ficheiros: variável ~40m → (18+40)×1.10 = 63.8 → **1h15m**
- CRUD completo multi-ficheiro: variável ~70m → (18+70)×1.10 = 96.8 → **1h45m**
- Reestruturação de módulo: variável ~150m → (18+150)×1.10 = 184.8 → **3h**

**Regras:**
- Componentes fixas são IMUTÁVEIS — 18m, não ajustar
- O agent estima APENAS a componente variável, com base no que vê no código
- Arredondar ao múltiplo de 15m mais próximo
- Estimativa MÍNIMA: **30m** (nenhum ticket demora menos)
- Se incerto, arredondar para cima
- O planning só altera a estimativa se a complexidade mudar vs o audit
- O DA valida se a estimativa é realista no PLANNING-REVIEW
- No ticket escrever APENAS o tempo total (ex: `**Estimativa:** 45m`), sem decomposição

### Campo "Introduzido" (obrigatório nos findings do audit)

Usar `git log` ou `git blame` no ficheiro afectado para estimar QUANDO o código problemático apareceu.

**Formato:** `**Introduzido:** ~YYYY-MM` (apenas mês/ano aproximado)

**Propósito:** Avaliar há quanto tempo o problema existe e qual o impacto acumulado.
- Bug de 6 meses tem mais impacto que bug de 1 semana
- Ajuda a priorizar: problemas antigos afectaram mais utilizadores

**PROIBIDO:**
- Mencionar nomes de autores
- Mencionar commits específicos (SHAs)
- Atribuir culpa — o objectivo é rastrear impacto temporal, NÃO culpar

**Sub-secções `#####` so aparecem quando planning MODIFICA o conteudo original.** Se confirmado sem alterações, omitir.

**FORWARD-REFERENCE RULE:** Quando sub-secções `#####` existem dentro de `#### Planeamento`, adicionar uma nota no TOPO da secção original correspondente: `*(ver versão actualizada em Planeamento abaixo)*`. Isto indica ao leitor que a versão original foi substituída. A secção original mantém-se imutável — apenas a nota é adicionada.

## CU Manager-Added Sections

Além de `#### Planeamento`, o CU Manager adiciona estas secções durante Phase 3 (specialists NÃO as escrevem):
- **`#### Feedback Humano`** — entre `#### Como Testar` e `#### Planeamento`, SE existem comentários ClickUp
- **`#### Decisões Planning`** — após `#### Planeamento`, contém verdicts do DA + Investigation + Maestro

## Audit Sections IMMUTABLE

As secções originais do audit (`#### Problema`, `#### Impacto`, etc.) são **IMUTÁVEIS**. Versões refinadas vão DENTRO de `#### Planeamento` como sub-secções `#####`.
