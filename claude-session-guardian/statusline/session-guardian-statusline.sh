#!/bin/bash
# claude-session-guardian — Statusline writer
# Version: 1.0.3
#
# PURPOSE: Receives Claude Code statusline JSON on stdin, extracts rate_limits,
# persists them atomically to <CLAUDE_BASE>/session-guardian/rate-state.json so
# the session-guardian skill can read them between turns. Emits a minimal
# statusline to stdout for display.
#
# CLAUDE_BASE is $CLAUDE_CONFIG_DIR if set (CLDP, CLDW, or other custom Claude
# Code installations), otherwise $HOME/.claude. This ensures state lives next
# to the user's settings.json regardless of installation layout, and that
# parallel installations (e.g. CLDP + CLDW) keep their state isolated.
#
# SECURITY:
# - Symlink rejection (defence against attack redirecting writes to sensitive
#   files like ~/.ssh/authorized_keys, ~/.claude-personal/settings.json).
# - Atomic write to same-directory .tmp (not $TMPDIR — cross-filesystem mv is
#   not atomic on some macOS configurations).
# - Restrictive permissions (0600) on the state file.
# - Type validation of rate_limits fields; malformed payloads are rejected
#   without writing (fail-closed).
#
# INSTALLED BY: /session-guardian:setup skill — which updates settings.json
# statusLine.command to point to this script with absolute path.

set -u

CLAUDE_BASE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE_DIR="$CLAUDE_BASE/session-guardian"
STATE_FILE="$STATE_DIR/rate-state.json"
TMP_FILE="$STATE_DIR/rate-state.json.tmp.$$"
LOG_FILE="$STATE_DIR/statusline-errors.log"

log_error() {
    mkdir -p "$STATE_DIR" 2>/dev/null
    echo "[$(date -u +%FT%TZ)] $1" >> "$LOG_FILE" 2>/dev/null
}

# ── Read stdin (Claude Code statusline payload) ──────────────────────────────
INPUT=$(cat)

# ── Minimal statusline output (always emit, even on error) ───────────────────
MODEL=$(printf '%s' "$INPUT" | jq -r '.model.display_name // .model.name // "Claude"' 2>/dev/null)

# ── Extract rate_limits with defensive parsing ───────────────────────────────
# Payload shape verified at runtime (V4 validation). Fall back gracefully.
# resets_at observed in two shapes: ISO-8601 string ("2026-04-24T19:30:00Z")
# OR Unix epoch (1777082400). Script accepts both — see normalize_resets_at.
PCT_5H=$(printf '%s' "$INPUT" | jq -r '.rate_limits.five_hour.used_percentage // .rate_limits.fiveHour.used_percentage // empty' 2>/dev/null)
RESETS_5H_RAW=$(printf '%s' "$INPUT" | jq -r '.rate_limits.five_hour.resets_at // .rate_limits.fiveHour.resets_at // empty' 2>/dev/null)
PCT_7D=$(printf '%s' "$INPUT" | jq -r '.rate_limits.seven_day.used_percentage // .rate_limits.sevenDay.used_percentage // empty' 2>/dev/null)
RESETS_7D_RAW=$(printf '%s' "$INPUT" | jq -r '.rate_limits.seven_day.resets_at // .rate_limits.sevenDay.resets_at // empty' 2>/dev/null)

# ── Type validation ──────────────────────────────────────────────────────────
is_valid_pct() {
    [ -n "$1" ] && [[ "$1" =~ ^[0-9]+$ ]] && [ "$1" -ge 0 ] && [ "$1" -le 100 ]
}
is_valid_iso8601() {
    [ -n "$1" ] && [[ "$1" =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2} ]]
}
# Unix epoch in seconds: 9-11 digits covers 1973-04-26 to 5138-11-16, i.e. any
# realistic resets_at value. We exclude shorter ints to avoid coincidence with
# malformed input, and longer ints (milliseconds) which would need /1000.
is_valid_epoch() {
    [ -n "$1" ] && [[ "$1" =~ ^[0-9]{9,11}$ ]]
}
# Convert Unix epoch (seconds) to ISO-8601 UTC. BSD date (macOS) uses -r;
# GNU date (Linux) uses -d "@…". Fall through to whichever works.
epoch_to_iso() {
    date -u -r "$1" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null \
        || date -u -d "@$1" +"%Y-%m-%dT%H:%M:%SZ" 2>/dev/null
}
# Returns canonical ISO-8601 from either ISO-8601 or epoch input. Empty if invalid.
normalize_resets_at() {
    local v="$1"
    if is_valid_iso8601 "$v"; then
        printf '%s' "$v"
    elif is_valid_epoch "$v"; then
        epoch_to_iso "$v"
    fi
}

# Normalize resets_at fields (accept both ISO and Unix epoch)
RESETS_5H=$(normalize_resets_at "$RESETS_5H_RAW")
RESETS_7D=$(normalize_resets_at "$RESETS_7D_RAW")

VALID=1
if [ -n "$PCT_5H" ] && ! is_valid_pct "$PCT_5H"; then
    log_error "invalid used_percentage_5h: $PCT_5H"
    VALID=0
fi
if [ -n "$RESETS_5H_RAW" ] && [ -z "$RESETS_5H" ]; then
    log_error "invalid resets_at_5h (not ISO-8601 nor epoch): $RESETS_5H_RAW"
    VALID=0
fi

# ── Ensure state dir exists (safe) ───────────────────────────────────────────
if [ ! -d "$STATE_DIR" ]; then
    mkdir -p "$STATE_DIR" 2>/dev/null || {
        log_error "cannot create $STATE_DIR"
        # Still emit statusline — don't break UX
        printf '%s\n' "$MODEL"
        exit 0
    }
fi

# ── Symlink rejection ────────────────────────────────────────────────────────
if [ -L "$STATE_DIR" ]; then
    log_error "$STATE_DIR is a symlink — refusing to write"
    printf '%s\n' "$MODEL"
    exit 0
fi
if [ -L "$STATE_FILE" ]; then
    log_error "$STATE_FILE is a symlink — refusing to write"
    printf '%s\n' "$MODEL"
    exit 0
fi

# ── Write rate-state.json if we have valid data ──────────────────────────────
if [ "$VALID" -eq 1 ] && [ -n "$PCT_5H" ] && [ -n "$RESETS_5H" ]; then
    UPDATED_AT=$(date -u +"%Y-%m-%dT%H:%M:%SZ")

    # Build JSON with jq for correctness
    if ! jq -n \
        --argjson pct5h "$PCT_5H" \
        --arg resets5h "$RESETS_5H" \
        --arg pct7d "${PCT_7D:-null}" \
        --arg resets7d "${RESETS_7D:-}" \
        --arg updated "$UPDATED_AT" \
        '{
            used_percentage_5h: $pct5h,
            resets_at_5h: $resets5h,
            used_percentage_7d: (if $pct7d == "null" or $pct7d == "" then null else ($pct7d|tonumber) end),
            resets_at_7d: (if $resets7d == "" then null else $resets7d end),
            updated_at: $updated
        }' > "$TMP_FILE" 2>/dev/null; then
        log_error "jq failed to build state JSON"
        rm -f "$TMP_FILE" 2>/dev/null
    else
        # Restrictive permissions before publishing
        chmod 0600 "$TMP_FILE" 2>/dev/null
        # Atomic rename (same filesystem)
        if ! mv -f "$TMP_FILE" "$STATE_FILE" 2>/dev/null; then
            log_error "mv to $STATE_FILE failed"
            rm -f "$TMP_FILE" 2>/dev/null
        fi
    fi
fi

# ── Emit statusline ──────────────────────────────────────────────────────────
# Format: Model · 5h PCT% (reset HH:MM) · 7d PCT%
LINE="$MODEL"

if is_valid_pct "$PCT_5H"; then
    RESET_SHORT=""
    if is_valid_iso8601 "$RESETS_5H"; then
        # Extract HH:MM — portable across BSD/GNU date
        RESET_SHORT=" (reset ${RESETS_5H:11:5})"
    fi
    LINE="$LINE · 5h ${PCT_5H}%${RESET_SHORT}"
fi

if is_valid_pct "$PCT_7D"; then
    LINE="$LINE · 7d ${PCT_7D}%"
fi

printf '%s\n' "$LINE"
exit 0
