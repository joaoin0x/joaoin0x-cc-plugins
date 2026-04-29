#!/bin/bash
# claude-session-guardian — Background detector
# Version: 1.1.0
#
# PURPOSE: Polls rate-state.json every 60s. Emits a stdout line ONLY on:
#   - Zone UPGRADE (yellow/red/critical reached)
#   - Health pulse (every 30 min, proves monitor is alive)
#
# Each stdout line is delivered to Claude as a notification, prompting it
# to invoke /session-guardian:react with the supplied args. The reactor
# then decides what to do (warn user, send messages to subagents, HARD
# STOP). This keeps the detector lightweight (zero token cost while running)
# and concentrates all decision logic + tool access in the reactor skill.
#
# Downgrades are deliberately silent — the 5h window only goes to 0% at
# reset, by which time the session has either been paused (HARD STOP) or
# the user manually stopped the guardian. Either path already cleans flags.
# Edge case (reset without HARD STOP, with stale flags) is covered by the
# reactor doing defensive cleanup in green/green-high zones on the next
# health pulse (≤30 min after reset).
#
# AUTO-STARTED by the plugin's monitors.json manifest. Do not invoke directly.

set -u

CLAUDE_BASE="${CLAUDE_CONFIG_DIR:-$HOME/.claude}"
STATE_DIR="$CLAUDE_BASE/session-guardian"
RATE_STATE="$STATE_DIR/rate-state.json"
LAST_ZONE_FILE="$STATE_DIR/.monitor-last-zone"
LAST_HEALTH_FILE="$STATE_DIR/.monitor-last-health"

POLL_INTERVAL=60         # seconds between rate-state checks
HEALTH_INTERVAL=1800     # seconds between health pulses (30 min)

mkdir -p "$STATE_DIR" 2>/dev/null

# Initialize health pulse anchor on first run so the first pulse is emitted
# HEALTH_INTERVAL seconds after monitor start (not immediately). Otherwise
# LAST_HEALTH=0 makes (NOW - 0) >> HEALTH_INTERVAL and the first iteration
# fires a health pulse, polluting startup.
if [ ! -f "$LAST_HEALTH_FILE" ]; then
    printf '%s' "$(date +%s)" > "$LAST_HEALTH_FILE"
fi

# ── Helpers ──────────────────────────────────────────────────────────────────

zone_for_pct() {
    local p="$1"
    if [ "$p" -lt 50 ]; then echo "green"
    elif [ "$p" -lt 70 ]; then echo "green-high"
    elif [ "$p" -lt 82 ]; then echo "yellow"
    elif [ "$p" -lt 90 ]; then echo "red"
    else echo "critical"
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

emit_health() {
    local pct="$1" zone="$2" mins="$3"
    echo "[session-guardian] HEALTHY zone=${zone} pct=${pct} mins_left=${mins}"
    echo "ACTION: invoke /session-guardian:react with args \"${zone} ${pct} ${mins}\""
}

# ── Main loop ────────────────────────────────────────────────────────────────

while true; do
    # Refuse symlinks (consistent with statusline writer)
    if [ -L "$RATE_STATE" ]; then
        sleep "$POLL_INTERVAL"
        continue
    fi

    if [ -f "$RATE_STATE" ]; then
        PCT=$(jq -r '.used_percentage_5h // empty' "$RATE_STATE" 2>/dev/null)
        RESETS=$(jq -r '.resets_at_5h // empty' "$RATE_STATE" 2>/dev/null)

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
                # Downgrade — suppress notification but keep state in sync.
                # The health pulse will eventually trigger reactor's
                # defensive cleanup if flags are stale.
                printf '%s' "$CURRENT_ZONE" > "$LAST_ZONE_FILE"
            fi
            # else: same zone, no action

            # Health pulse (only if we didn't already emit this iteration)
            if [ "$EMITTED" -eq 0 ]; then
                NOW=$(date +%s)
                LAST_HEALTH=$(cat "$LAST_HEALTH_FILE" 2>/dev/null || echo 0)
                if [ $(( NOW - LAST_HEALTH )) -ge "$HEALTH_INTERVAL" ]; then
                    emit_health "$PCT" "$CURRENT_ZONE" "$MINS"
                    printf '%s' "$NOW" > "$LAST_HEALTH_FILE"
                fi
            fi
        fi
    fi

    sleep "$POLL_INTERVAL"
done
