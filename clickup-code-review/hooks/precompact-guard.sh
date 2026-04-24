#!/bin/bash
# ClickUp Code Review Plugin — PreCompact Guard Hook
# Hook: PreCompact (no matcher — fires on every /compact and autocompact)
#
# PURPOSE: Block compaction while a review workflow is active. Mid-workflow
# compaction risks losing context not yet persisted to code-reviews/:
# SendMessage trail, in-flight findings, triangle DA+Investigation state,
# wave plan under construction.
#
# SECURITY: Reads guard marker to display state. Symlinks rejected. Marker
# content sanitised (control chars stripped) before printing to stderr to
# prevent ANSI/terminal injection from a hostile marker (e.g. malicious repo).
#
# INSTALLED BY: Plugin hooks/hooks.json (auto-loaded when plugin is enabled).
#
# GUARD: Marker at $CLAUDE_PROJECT_DIR/code-reviews/.clickup-review-active.
#        Override: rm -f code-reviews/.clickup-review-active, then /compact.

# Defensive: if CLAUDE_PROJECT_DIR is unset, do nothing (no opinion).
# Otherwise the marker path would expand to "/code-reviews/..." absolute root
# and falsely match any such directory on the system.
if [ -z "${CLAUDE_PROJECT_DIR:-}" ]; then
    exit 0
fi

GUARD_MARKER="${CLAUDE_PROJECT_DIR}/code-reviews/.clickup-review-active"

# Reject symlinks: a hostile repo could ship this as a symlink to .env,
# .ssh/id_rsa, /etc/passwd, etc. and exfiltrate bytes via stderr.
if [ -L "$GUARD_MARKER" ]; then
    echo "[clickup-code-review] Marker e symlink — recusado por seguranca." >&2
    exit 2
fi

# No marker → no block.
if [ ! -f "$GUARD_MARKER" ]; then
    exit 0
fi

# Read marker content (captures TOCTOU: if marker is removed between [-f]
# and head, STATE is empty but we still block — acceptable, user retries).
# Sanitise: strip every byte that is not printable ASCII or whitespace, to
# prevent ANSI escape injection, cursor manipulation, or OSC hyperlinks from
# a hostile marker payload. LC_ALL=C keeps tr byte-wise (not locale-aware).
STATE=$(head -c 200 "$GUARD_MARKER" 2>/dev/null | LC_ALL=C tr -cd '\11\12\15\40-\176')

cat <<EOF >&2
[clickup-code-review] Compactacao BLOQUEADA — review activa.

Marker: $GUARD_MARKER
Estado: ${STATE:-(vazio)}

Razao do bloqueio:
  Compactacao a meio de um workflow (audit/planning/fix/testing) pode
  perder contexto critico: SendMessage trail, findings em transito,
  validacao triangle DA+Investigation, wave plan em construcao.

Opcoes:
  1. Aguardar o Maestro chegar a checkpoint seguro (fim de wave/fase)
     — neste ponto o marker e removido automaticamente.
  2. Se precisa compactar AGORA (caso excepcional):
       rm -f code-reviews/.clickup-review-active
       /compact
     NOTA: o rm vai pedir aprovacao manual — e intencional. Garante
     visibilidade quando o PreCompact guard e contornado (proteccao
     contra prompt injection que tente bypassar o bloqueio).
     A skill activa recria o marker na proxima operacao.
EOF

exit 2
