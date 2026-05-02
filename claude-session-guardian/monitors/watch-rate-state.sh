#!/bin/bash
# claude-session-guardian — Background detector
# Version: 1.1.2
#
# PURPOSE: Polls rate-state.json with adaptive cadence (faster in active
# zones). Emits a stdout line ONLY when a real signal warrants the reactor's
# attention:
#   - ZONE_UPGRADE — transition into a higher 5h zone (yellow/red/critical)
#   - RESET_DETECTED — significant downgrade (any active zone → green/
#     green-high), so reactor can clean stale flags from a non-HARD-STOP exit
#   - WEEKLY_WARN / WEEKLY_CRITICAL — 7d window crossings
#
# v1.1.2 (2026-05-02) reverses the v1.1.0 design decision to emit periodic
# HEALTHY pulses. Real-world data showed:
#   - Idle session over 14h: 26 health pulses, 26 reactor invocations,
#     ~181 Bash calls — pure overhead with no actionable outcome.
#   - 30-min cadence in yellow zone is far too slow for sessions where pct
#     can climb 30pp in 30 min. By the time the next pulse fires, it's too
#     late to alert.
#
# New design (v1.1.2):
#   - No periodic heartbeats. Reactor only runs on real events.
#   - Cadence is adaptive to current zone (faster when stakes are higher):
#     green/green-high → 5 min, yellow → 2 min, red → 1 min, critical → 1 min.
#   - RESET_DETECTED replaces the "defensive cleanup via health pulse" path:
#     fires once on downgrade, not every 30 min in green.
#   - Consecutive-error auto-pause from v1.1.1 still applies.
#
# AUTO-STARTED by the plugin's monitors.json manifest. Do not invoke directly.

set -u

CLAUDE_BASE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE_DIR="$CLAUDE_BASE/session-guardian"
RATE_STATE="$STATE_DIR/rate-state.json"
LAST_ZONE_FILE="$STATE_DIR/.monitor-last-zone"
LAST_7D_ZONE_FILE="$STATE_DIR/.monitor-last-7d-zone"
REACTOR_STATUS_FILE="$STATE_DIR/.reactor-status"

# Adaptive poll intervals (seconds) — active zones poll faster
POLL_GREEN=300         # 5 min — silent monitoring
POLL_GREEN_HIGH=300    # 5 min — silent monitoring
POLL_YELLOW=120        # 2 min — pct can climb fast in this zone
POLL_RED=60            # 1 min — minutes-to-critical urgency
POLL_CRITICAL=60       # 1 min — HARD STOP path, but sanity poll

MAX_CONSECUTIVE_REACTOR_ERRORS=3   # stop emitting after this many errors

mkdir -p "$STATE_DIR" 2>/dev/null

# ── Helpers ──────────────────────────────────────────────────────────────────

# 5h zones (v1.1.1: HARD STOP at 85% not 90% — earlier intervention)
zone_for_pct() {
    local p="$1"
    if [ "$p" -lt 50 ]; then echo "green"
    elif [ "$p" -lt 65 ]; then echo "green-high"
    elif [ "$p" -lt 75 ]; then echo "yellow"
    elif [ "$p" -lt 85 ]; then echo "red"
    else echo "critical"
    fi
}

# 7d zones (NEW v1.1.1) — to prevent hitting monthly limit mid-workflow
zone_for_pct_7d() {
    local p="$1"
    if [ "$p" -lt 80 ]; then echo "weekly-ok"
    elif [ "$p" -lt 90 ]; then echo "weekly-warn"
    else echo "weekly-critical"
    fi
}

# Numeric rank for zone comparison (upgrade = strictly greater rank)
zone_rank() {
    case "$1" in
        green) echo 0 ;;
        green-high) echo 1 ;;
        yellow) echo 2 ;;
        red) echo 3 ;;
        critical) echo 4 ;;
        *) echo -1 ;;  # init or unknown
    esac
}

# Compute minutes until reset from ISO-8601 UTC. Output "?" if parsing fails.
mins_until_reset() {
    local iso="$1"
    [ -z "$iso" ] && { echo "?"; return; }
    local utc_str="${iso%Z}"
    local epoch
    # BSD (macOS): -j -u -f "<format-without-Z>" "<input-without-Z>"
    # GNU (Linux): -d accepts ISO with Z natively
    epoch=$(date -j -u -f "%Y-%m-%dT%H:%M:%S" "$utc_str" "+%s" 2>/dev/null \
            || date -d "$iso" "+%s" 2>/dev/null)
    [ -z "$epoch" ] && { echo "?"; return; }
    local now
    now=$(date -u +%s)
    local secs=$(( epoch - now ))
    [ "$secs" -lt 0 ] && secs=0
    echo $(( secs / 60 ))
}

emit_zone_upgrade() {
    local pct="$1" zone="$2" mins="$3"
    echo "[session-guardian] ZONE_UPGRADE pct=${pct} zone=${zone} mins_left=${mins}"
    echo "ACTION: invoke /session-guardian:react with args \"${zone} ${pct} ${mins}\""
}

# v1.1.2: emitted once on significant downgrade (active zone → green/green-high),
# replacing the periodic-pulse cleanup mechanism. Reactor checks for stale
# flags and cleans them; if there are none, it's a silent no-op.
emit_reset_detected() {
    local pct="$1" zone="$2" mins="$3" prev_zone="$4"
    echo "[session-guardian] RESET_DETECTED pct=${pct} zone=${zone} mins_left=${mins} from=${prev_zone}"
    echo "ACTION: invoke /session-guardian:react with args \"${zone} ${pct} ${mins} reset\""
}

emit_weekly() {
    local kind="$1" pct_7d="$2"
    echo "[session-guardian] ${kind} pct_7d=${pct_7d}"
    echo "ACTION: invoke /session-guardian:react with args \"${kind} ${pct_7d} weekly\""
}

# Read reactor status flag. Returns consecutive error count (0 if file absent or value is 0).
reactor_consecutive_errors() {
    [ -f "$REACTOR_STATUS_FILE" ] || { echo 0; return; }
    local v
    v=$(cat "$REACTOR_STATUS_FILE" 2>/dev/null)
    [[ "$v" =~ ^[0-9]+$ ]] && echo "$v" || echo 0
}

# Pick the next sleep duration based on current zone (adaptive cadence).
poll_interval_for_zone() {
    case "$1" in
        green) echo "$POLL_GREEN" ;;
        green-high) echo "$POLL_GREEN_HIGH" ;;
        yellow) echo "$POLL_YELLOW" ;;
        red) echo "$POLL_RED" ;;
        critical) echo "$POLL_CRITICAL" ;;
        *) echo "$POLL_GREEN" ;;
    esac
}

# ── Main loop ────────────────────────────────────────────────────────────────

CURRENT_ZONE="green"  # default until first read

while true; do
    # Refuse symlinks (consistent with statusline writer)
    if [ -L "$RATE_STATE" ]; then
        sleep "$(poll_interval_for_zone "$CURRENT_ZONE")"
        continue
    fi

    # Auto-pause output if reactor has been failing repeatedly (e.g. session
    # blocked by monthly limit). Avoids notification loops when reactor cannot
    # respond. Detector keeps polling state silently for when reactor recovers.
    REACTOR_ERRORS=$(reactor_consecutive_errors)
    if [ "$REACTOR_ERRORS" -ge "$MAX_CONSECUTIVE_REACTOR_ERRORS" ]; then
        sleep "$(poll_interval_for_zone "$CURRENT_ZONE")"
        continue
    fi

    if [ -f "$RATE_STATE" ]; then
        PCT=$(jq -r '.used_percentage_5h // empty' "$RATE_STATE" 2>/dev/null)
        RESETS=$(jq -r '.resets_at_5h // empty' "$RATE_STATE" 2>/dev/null)
        PCT_7D=$(jq -r '.used_percentage_7d // empty' "$RATE_STATE" 2>/dev/null)

        if [ -n "$PCT" ] && [[ "$PCT" =~ ^[0-9]+$ ]]; then
            CURRENT_ZONE=$(zone_for_pct "$PCT")
            LAST_ZONE=$(cat "$LAST_ZONE_FILE" 2>/dev/null || echo "init")
            MINS=$(mins_until_reset "$RESETS")
            CUR_RANK=$(zone_rank "$CURRENT_ZONE")
            LAST_RANK=$(zone_rank "$LAST_ZONE")

            EMITTED=0

            if [ "$CUR_RANK" -gt "$LAST_RANK" ]; then
                # Zone upgrade detected
                if [ "$LAST_ZONE" = "init" ] && [ "$CUR_RANK" -le 1 ]; then
                    # Silent startup in green/green-high — nothing to alert
                    :
                else
                    emit_zone_upgrade "$PCT" "$CURRENT_ZONE" "$MINS"
                    EMITTED=1
                fi
                printf '%s' "$CURRENT_ZONE" > "$LAST_ZONE_FILE"
            elif [ "$CUR_RANK" -lt "$LAST_RANK" ]; then
                # Downgrade — emit RESET_DETECTED only when going from an
                # active zone (yellow/red/critical) to a quiet zone
                # (green/green-high). This is the post-reset signal that
                # tells the reactor to clean stale flags. In all other
                # downgrade cases the reactor has nothing to do, so silent.
                if [ "$LAST_RANK" -ge 2 ] && [ "$CUR_RANK" -le 1 ]; then
                    emit_reset_detected "$PCT" "$CURRENT_ZONE" "$MINS" "$LAST_ZONE"
                    EMITTED=1
                fi
                printf '%s' "$CURRENT_ZONE" > "$LAST_ZONE_FILE"
            fi
            # else: same zone, no action — adaptive cadence keeps overhead low
        fi

        # Weekly window monitoring (independent from 5h zones)
        if [ -n "$PCT_7D" ] && [[ "$PCT_7D" =~ ^[0-9]+$ ]] && [ "$EMITTED" -eq 0 ]; then
            CURRENT_7D=$(zone_for_pct_7d "$PCT_7D")
            LAST_7D=$(cat "$LAST_7D_ZONE_FILE" 2>/dev/null || echo "weekly-ok")

            if [ "$CURRENT_7D" != "$LAST_7D" ]; then
                case "$CURRENT_7D" in
                    weekly-warn)
                        if [ "$LAST_7D" = "weekly-ok" ] || [ "$LAST_7D" = "init" ]; then
                            emit_weekly "WEEKLY_WARN" "$PCT_7D"
                            EMITTED=1
                        fi
                        ;;
                    weekly-critical)
                        emit_weekly "WEEKLY_CRITICAL" "$PCT_7D"
                        EMITTED=1
                        ;;
                esac
                printf '%s' "$CURRENT_7D" > "$LAST_7D_ZONE_FILE"
            fi
        fi
        # No more periodic health pulses — see v1.1.2 design rationale at top.
    fi

    sleep "$(poll_interval_for_zone "$CURRENT_ZONE")"
done
