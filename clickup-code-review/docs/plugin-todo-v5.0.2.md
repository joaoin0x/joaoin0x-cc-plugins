---
name: plugin-todo-v5.0.2
description: Post-test TODO items for ClickUp Code Review plugin — hook update gap + permission prompts
type: project
---

## Plugin v5.0.2 TODOs (identified during v5.0.1 test — 2026-03-13)

### Status Summary (updated 2026-03-15)
- **RESOLVED (15):** #2, #3, #4, #5, #6, #7, #8, #9, #10, #13 — fixed in SKILL.md, DA, CU Manager, hook. **v5.0.2 restructuring completed:** 3 shared skills created, 9 agents refactored (≤8K each), FORBIDDEN/spawn order/recovery added to Planning+Fix SKILL.md, /tmp paths migrated, setup Step 6 updated for plugin-bundled hooks. **Permission flood fix (2026-03-15):** 3 bugs found+fixed — `__SETTINGS_PATH__` placeholder not replaced in installed hook, wrong JSON response format (`{"decision":"approve"}` → `hookSpecificOutput`), hooks.json hooks don't apply to subagents (registered file-ops+SendMessage in settings.json).
- **PENDING (2):** #1 (hook auto-update — setup wizard detects version mismatch), #11 + #12 (need full 7-specialist test in clean session)
- **LOW PRIORITY (1):** #14 (idle notifications)
- **Files modified:** ALL agents/*.md, skills/shared/*.md (3 new), skills/*/SKILL.md (4 updated), plugin.json (5.0.2), docs/ (2 new)
- **Plugin version:** v5.0.2 (restructuring complete, permission fix applied 2026-03-15)
- **Cleanup:** `86c8qhbzn` — parent ticket criado durante testes funcionais (2026-03-10), mal criado, sem planning, está "ready for dev" indevidamente. Rever/fechar na próxima sessão.

1. **Hook not auto-updated on plugin install**
   - **Why:** When plugin updates (e.g., v4→v5.0.1), `plugin install` refreshes the cache but does NOT re-run setup Step 6. The hook at `~/.claude-personal/hooks/clickup-auto-approve.sh` stays at the old version.
   - **How to apply:** Either (a) setup wizard detects hook version mismatch and warns, or (b) add a SessionStart hook that checks hook version vs plugin version, or (c) plugin install triggers a post-install script.

2. **Excessive permission prompts during audit**
   - **Why:** The auto-approve hook only covers Bash tool (curl + cat/tee/mkdir). But CU Manager and specialists also use Write/Read tools which don't pass through the Bash hook. Without `bypassPermissions` mode, the user gets flooded with permission prompts.
   - **How to apply:** Consider adding PreToolUse hooks for Write and Read tools that auto-approve paths matching `.claude/code-reviews/` and `/tmp/findings/`. Or document that `bypassPermissions` is mandatory for audit agents.

3. **Duplicate mkdir by specialists — check before creating**
   - **Why:** CU Manager creates `/tmp/findings/` in Phase 1 (CREATE FOLDER TREE). But the specialist spawn template doesn't tell agents the folder already exists, so they run `mkdir -p /tmp/findings` again. This triggers a permission prompt for something already done — wasted user interaction.
   - **How to apply:** (a) Add to spawn template: "A pasta /tmp/findings/ JÁ FOI CRIADA pelo CU Manager. NÃO criar de novo." (b) General rule in SKILL.md: any agent creating dirs/files MUST check existence first (`[ -d ... ] || mkdir`). (c) Better yet: remove mkdir from specialist logic entirely — it's CU Manager's job.

4. **bypassPermissions não cobre Read/Write para /tmp/**
   - **Why:** Agents spawned with `bypassPermissions` still get permission prompts for Read tool on `/tmp/findings/` paths. The DA had to ask permission to read `/tmp/findings/security-specialist-1.md`. This path is outside the project dir, so even bypassPermissions may not cover it.
   - **How to apply:** (a) Add PreToolUse hooks for Read and Write matchers that auto-approve `/tmp/findings/` paths, or (b) investigate if bypassPermissions has path restrictions for /tmp/, or (c) use the project-scoped `.claude/code-reviews/` path instead of `/tmp/` for findings (eliminates the out-of-project-dir issue entirely — but loses the "ephemeral" nature of /tmp).

5. **User experience: too many permission prompts in first audit run**
   - **Why:** User had to approve: mkdir /tmp/findings (specialist), Read /tmp/findings/*.md (DA), plus potentially Write /tmp/findings/*.md (specialist writing findings). Each is a separate prompt. For a 7-category audit with many findings, this could be dozens of prompts.
   - **How to apply:** Consider a "pre-flight permissions" step in Phase 0 where Maestro asks the user ONCE to authorize all /tmp/findings/ and .claude/code-reviews/ operations for the session. Or: move everything to .claude/code-reviews/ (project-scoped, already in gitignore, bypassPermissions covers it).

6. **DECISÃO: Eliminar /tmp/findings/ — usar apenas .claude/code-reviews/**
   - **Why:** `/tmp/findings/` está fora do projecto. Claude Code trata como "outside working directory" e pede confirmação para Write/Read. O DA apanha um warning de symlink ao tentar modificar `/private/tmp/findings/security-specialist-1.md`. Isto bloqueia o fluxo inteiro — o DA precisa de escrever o verdict no ficheiro e não consegue sem aprovação manual.
   - **Root cause:** `/tmp/` no macOS é um symlink para `/private/tmp/`. Claude Code detecta isto como "outside working directory via symlink" — uma protecção de segurança legítima que não podemos contornar.
   - **How to apply:** ELIMINAR `/tmp/findings/` completamente. Specialists escrevem findings directamente para `.claude/code-reviews/{review_dir}/findings/{specialist}-{n}.md`. DA escreve verdict no mesmo ficheiro. CU Manager lê de lá e move para `{area_dir}/{task_id}.md` ao criar o ticket. Tudo dentro do projecto, coberto por gitignore, sem problemas de permissões.
   - **Impact:** Resolve TODO #2, #3, #4, #5 de uma vez. Arquitectura simplifica-se — um único directório em vez de dois.
   - **Priority:** CRITICAL — sem isto o audit não funciona sem intervenção manual constante.

7. **Hook só cobre Bash matcher — precisa de Write e Read matchers também**
   - **Why:** O hook PreToolUse tem matcher `"Bash"` apenas. Quando o CU Manager usa o Write tool para criar `.claude/code-reviews/.../86c8udkc3.md`, o hook não intercepta — o user leva prompt. Mesmo com `bypassPermissions`, o Write tool para `.claude/code-reviews/` ainda pede confirmação.
   - **How to apply:** Adicionar 2 matchers ao hook (ou criar hooks separados): (a) `"Write"` matcher que auto-aprova paths com `.claude/code-reviews/`, (b) `"Read"` matcher que auto-aprova paths com `.claude/code-reviews/` e `/tmp/findings/`. Setup wizard Step 6 precisa de registar os 3 matchers (Bash + Write + Read).

8. **Hook multi-statement scripts — #!/bin/bash no início pode falhar o match**
   - **Why:** O CU Manager enviou um script multi-statement com `#!/bin/bash` header para criar ticket (POST curl). O hook pode não estar a reconhecer o padrão `curl -X POST...api.clickup.com` quando está embrulhado num script com shebang e variáveis. Verificar se o grep no hook apanha correctamente o URL dentro de scripts complexos.
   - **How to apply:** Testar o hook com o exact script que o CU Manager gerou. Se falhar, ajustar o regex para ser mais permissivo com multi-line scripts.

9. **CRITICAL: Debate DA↔Specialist falha quando specialist está ocupado**
   - **Why:** O DA enviou challenge ao specialist sobre finding 3 (Cache::flush). O specialist estava ocupado a escrever findings 4 e 5 e NUNCA respondeu ao debate. O DA esperou, não obteve resposta, e rejeitou unilateralmente após 1 round sem debate real. O specialist depois aceitou passivamente a rejeição sem ter participado no debate. O finding pode até merecer rejeição (DA tinha bons argumentos sobre Redis DBs separados), mas o PROCESSO falhou — não houve contraditório.
   - **Root cause:** O specialist não tem instrução para PAUSAR a escrita de novos findings quando recebe um challenge do DA. O SKILL.md diz "max 3 debate rounds" mas não diz que o specialist DEVE responder antes de continuar.
   - **How to apply:** (a) Regra explícita no spawn template: "Se receberes uma mensagem do DA a questionar um finding, PÁRA o que estás a fazer e RESPONDE IMEDIATAMENTE. O debate tem prioridade sobre novos findings." (b) DA deve esperar pelo menos 60s antes de declarar "specialist não respondeu". (c) Se specialist não responde após timeout, DA deve escalar ao Maestro em vez de rejeitar unilateralmente. (d) Maestro pode então fazer ping ao specialist e forçar a resposta. (e) O verdict NUNCA deve dizer "Debate rounds: 1 (specialist não respondeu ao challenge)" — isto é uma falha de processo, não um debate.
   - **Impact:** Findings potencialmente válidos podem ser silenciosamente descartados. O user perde confiança no sistema de review.
   - **Priority:** CRITICAL — compromete a integridade do processo de review.

10. **Maestro fez shutdown sem ordem do user**
    - **Why:** O Maestro enviou shutdown_request aos 3 agentes sem o user ter pedido. O SKILL.md (Agent Governance) diz "Agents stay on standby until user gives shutdown order" e a team-methodology diz o mesmo. O Maestro assumiu que o audit estar completo = pode desligar agentes.
    - **How to apply:** (a) Adicionar ao SKILL.md Maestro Checklist: "NUNCA enviar shutdown_request sem instrução explícita do user. Apresentar summary e ESPERAR." (b) Adicionar à secção FORBIDDEN: "NUNCA desligar agentes sem ordem directa do user — apresentar resultados e aguardar instrução."
    - **Priority:** MAJOR — viola a governança de agentes e o princípio de "step-by-step, await confirmation".

11. **Teste v5.0.1 inconclusivo para context overflow**
    - **Why:** O teste correu com apenas 1 specialist (security). O problema de context overflow no v5.0 era causado por 7-8 agentes em paralelo a enviar findings pelo contexto do Maestro. Com 1 specialist, não houve overflow — mas isso era expectável mesmo sem as mudanças v5.0.1. Não se pode afirmar que a arquitectura file-based resolve o problema até testar com 7 specialists em simultâneo.
    - **How to apply:** O próximo teste DEVE correr com todas as categorias (security + backend + frontend + quality + complexity + qa-unit + qa-e2e) para validar se file-based communication + execução faseada resolvem o context overflow.
    - **Priority:** HIGH — sem este teste, a claim principal do v5.0.1 fica por validar.

12. **Context overflow aconteceu — mas contexto não estava limpo**
    - **Why:** A sessão fez context overflow ~34 min após iniciar o audit. MAS a sessão já vinha carregada com trabalho prévio (fixes ao plugin, skill-reviewer, plugin-validator, remoção de Co-Authored-By). O contexto NÃO estava limpo quando o audit começou. Não se pode atribuir o overflow ao audit em si.
    - **Root cause inconclusivo:** Pode ter sido (a) contexto prévio + audit, (b) Maestro side-work durante audit (editar TODOs, escrever memórias), ou (c) combinação de ambos. Impossível isolar sem sessão dedicada.
    - **How to apply:** (a) Próximo teste FULL deve começar numa sessão limpa. (b) Regra de higiene: Maestro não deve fazer side-work pesado durante audit activo. (c) Testar e medir — não assumir.
    - **Priority:** HIGH — fica por validar numa sessão limpa com 7 specialists.

13. **Maestro violou regra FORBIDDEN — leu conteúdo de findings**
    - **Why:** O Maestro leu `/tmp/findings/security-specialist-3.md` para verificar se o DA tinha escrito verdict. Também leu `/tmp/findings/security-coverage-assessment.md`. O SKILL.md diz "NUNCA ler /tmp files" com excepção ÚNICA para deadlocks (max 3 rounds esgotados). Verificar status de verdict NÃO é deadlock — o Maestro devia ter perguntado ao DA via SendMessage.
    - **How to apply:** (a) Reforçar no SKILL.md: "Para saber o status de um finding, PERGUNTAR ao DA via SendMessage. NUNCA ler o ficheiro /tmp directamente." (b) A leitura do security-coverage-assessment.md é discutível — o SKILL.md diz que o DA escreve para ficheiro, mas não diz explicitamente que o Maestro o deve ler. Clarificar: DA deve enviar um RESUMO do assessment via SendMessage, Maestro só lê o ficheiro se precisar de detalhes.
    - **Priority:** MAJOR — derrota o propósito do file-based isolation. Com 50+ findings, ler ficheiros injecta conteúdo massivo no contexto do Maestro.

14. **Idle notifications excessivas — impacto negligível mas desnecessárias**
    - **Why:** 16 idle notifications durante o audit (~120 bytes cada = ~1.9KB total). Num contexto de 200K tokens (~800KB), isto é ~0.2% — impacto negligível. Não é causa de overflow.
    - **How to apply:** LOW priority. Se quisermos optimizar: idle notifications apenas após 120s de inactividade. Mas não é urgente — o ganho é mínimo.
    - **Priority:** LOW — noise cosmético, não contribui materialmente para overflow.
