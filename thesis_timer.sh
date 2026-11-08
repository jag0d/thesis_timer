#!/usr/bin/env bash
#
# thesis_timer.sh - A persistent stopwatch for tracking thesis work.
#
# Usage:
#   ./thesis_timer.sh        # Resumes timing from previous accumulated value
#   ./thesis_timer.sh zero   # Starts timing from 0 (resets accumulated time)
#
# Stop the stopwatch at any time by pressing CTRL+D (sends EOF).
#

set -u

# Resolve the absolute path of the directory where this script is located
SCRIPT_DIR="$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" &>/dev/null && pwd)"
SAVE_FILE="${THESIS_TIMER_FILE:-"$SCRIPT_DIR/thesis_time.txt"}"

# Terminal color codes (if connected to a terminal and NO_COLOR is not set)
if [ -t 1 ] && [ -z "${NO_COLOR:-}" ]; then
    C_RESET="\033[0m"
    C_BOLD="\033[1m"
    C_CYAN="\033[1;36m"
    C_GREEN="\033[1;32m"
    C_YELLOW="\033[1;33m"
    C_DIM="\033[90m"
else
    C_RESET=""
    C_BOLD=""
    C_CYAN=""
    C_GREEN=""
    C_YELLOW=""
    C_DIM=""
fi

# Format seconds into digital display (e.g., 01:23:45 or 1d 02:23:45)
format_time() {
    local t=$1
    local days=$(( t / 86400 ))
    local hours=$(( (t % 86400) / 3600 ))
    local mins=$(( (t % 3600) / 60 ))
    local secs=$(( t % 60 ))

    if [ "$days" -gt 0 ]; then
        printf "%dd %02d:%02d:%02d" "$days" "$hours" "$mins" "$secs"
    else
        printf "%02d:%02d:%02d" "$hours" "$mins" "$secs"
    fi
}

# Format seconds into human-readable string (e.g., 1d 2h 0m 45s)
format_human() {
    local t=$1
    local days=$(( t / 86400 ))
    local hours=$(( (t % 86400) / 3600 ))
    local mins=$(( (t % 3600) / 60 ))
    local secs=$(( t % 60 ))

    local parts=()
    [ "$days" -gt 0 ] && parts+=("${days}d")
    { [ "$hours" -gt 0 ] || [ "$days" -gt 0 ]; } && parts+=("${hours}h")
    { [ "$mins" -gt 0 ] || [ "$hours" -gt 0 ] || [ "$days" -gt 0 ]; } && parts+=("${mins}m")
    parts+=("${secs}s")

    local str="${parts[*]}"
    if [ "$days" -gt 0 ]; then
        local total_h=$(( t / 3600 ))
        str="$str (${total_h}h ${mins}m ${secs}s total)"
    fi
    echo "$str"
}

# Load previously accumulated seconds from the save file
load_saved_time() {
    local val=""
    if [ -f "$SAVE_FILE" ]; then
        # Look for TOTAL_SECONDS=<digits>
        val=$(grep -E '^[[:space:]]*TOTAL_SECONDS=[0-9]+' "$SAVE_FILE" 2>/dev/null | head -n1 | cut -d= -f2 | tr -d '[:space:]')
        # Fallback to plain integer if file was manually edited
        if [ -z "$val" ]; then
            val=$(grep -E '^[[:space:]]*[0-9]+[[:space:]]*$' "$SAVE_FILE" 2>/dev/null | head -n1 | tr -d '[:space:]')
        fi
    fi
    echo "${val:-0}"
}

# Save accumulated seconds to file in a clean, human-readable format
save_time() {
    local total=$1
    local fmt
    fmt=$(format_human "$total")
    local timestamp
    timestamp=$(date +"%Y-%m-%d %H:%M:%S")

    # Atomic write to prevent file corruption
    local tmp_file="${SAVE_FILE}.tmp.$$"
    cat > "$tmp_file" <<EOF
# Thesis Stopwatch - Accumulated Time
# This file is automatically loaded and updated by thesis_timer.sh.
TOTAL_SECONDS=$total
FORMATTED=$(format_time "$total") ($fmt)
LAST_UPDATED=$timestamp
EOF
    mv -f "$tmp_file" "$SAVE_FILE"
}

# Parse command-line arguments
RESET_ZERO=false

if [ $# -gt 0 ]; then
    case "$1" in
        zero|ZERO|0|--zero)
            RESET_ZERO=true
            ;;
        -h|--help|help)
            echo -e "${C_BOLD}Usage:${C_RESET} $(basename "$0") [zero]"
            echo ""
            echo "A persistent stopwatch for tracking thesis work."
            echo ""
            echo -e "${C_BOLD}Arguments:${C_RESET}"
            echo "  (none)      Resume timing from previously accumulated value."
            echo "  zero        Reset stopwatch and start timing from 0."
            echo "  -h, --help  Show this help message and exit."
            echo ""
            echo -e "${C_BOLD}Controls:${C_RESET}"
            echo -e "  Press ${C_YELLOW}[CTRL+D]${C_RESET} (EOF) to stop the stopwatch and save accumulated time."
            exit 0
            ;;
        *)
            echo "Error: Unknown argument '$1'" >&2
            echo "Usage: $(basename "$0") [zero]" >&2
            exit 1
            ;;
    esac
fi

# Determine starting accumulated seconds
if [ "$RESET_ZERO" = true ]; then
    ACCUMULATED_SECONDS=0
else
    ACCUMULATED_SECONDS=$(load_saved_time)
fi

# Track start time and session state
START_TIME=$(date +%s)
SESSION_SECS=0
TOTAL_SECS=$ACCUMULATED_SECONDS
CLEANED_UP=0

# Save terminal state if attached to a terminal
SAVED_TTY=""
if [ -t 0 ]; then
    SAVED_TTY=$(stty -g 2>/dev/null || true)
    # Disable terminal echo so keystrokes don't disturb the display
    stty -echo 2>/dev/null || true
fi

cleanup() {
    [ "$CLEANED_UP" -eq 1 ] && return
    CLEANED_UP=1

    # Calculate final elapsed times
    local now
    now=$(date +%s)
    SESSION_SECS=$(( now - START_TIME ))
    [ "$SESSION_SECS" -lt 0 ] && SESSION_SECS=0
    TOTAL_SECS=$(( ACCUMULATED_SECONDS + SESSION_SECS ))

    # Save to file
    save_time "$TOTAL_SECS"

    # Restore terminal settings
    if [ -t 0 ] && [ -n "$SAVED_TTY" ]; then
        stty "$SAVED_TTY" 2>/dev/null || stty echo 2>/dev/null || true
    fi
    if [ -t 1 ]; then
        tput cnorm 2>/dev/null || printf "\033[?25h" 2>/dev/null || true
    fi

    # Display exit summary
    echo ""
    echo -e "${C_DIM}--------------------------------------------------${C_RESET}"
    echo -e " ${C_GREEN}Stopwatch stopped.${C_RESET}"
    echo -e " Session time:           ${C_BOLD}$(format_time "$SESSION_SECS")${C_RESET} ($(format_human "$SESSION_SECS"))"
    echo -e " Total accumulated time: ${C_CYAN}${C_BOLD}$(format_time "$TOTAL_SECS")${C_RESET} ($(format_human "$TOTAL_SECS"))"
    echo -e " Saved to:               ${C_DIM}$SAVE_FILE${C_RESET}"
    echo -e "${C_DIM}==================================================${C_RESET}"
}

trap cleanup EXIT
trap 'exit 0' INT TERM HUP

# Print header
echo -e "${C_DIM}==================================================${C_RESET}"
echo -e "             ${C_BOLD}Thesis Stopwatch${C_RESET}"
echo -e "${C_DIM}==================================================${C_RESET}"
if [ "$RESET_ZERO" = true ]; then
    echo -e " Mode:       ${C_YELLOW}Starting fresh from 00:00:00 (reset)${C_RESET}"
else
    echo -e " Mode:       Resumed from ${C_CYAN}$(format_time "$ACCUMULATED_SECONDS")${C_RESET} ($(format_human "$ACCUMULATED_SECONDS"))"
fi
echo -e " Exit:       Press ${C_YELLOW}[CTRL+D]${C_RESET} (EOF) to stop and save."
echo -e "${C_DIM}--------------------------------------------------${C_RESET}"

# Hide cursor if terminal
if [ -t 1 ]; then
    tput civis 2>/dev/null || printf "\033[?25l" 2>/dev/null || true
fi

LAST_DISPLAYED_SEC=-1
LAST_AUTOSAVE=$START_TIME

# Main timing loop
while true; do
    NOW=$(date +%s)
    SESSION_SECS=$(( NOW - START_TIME ))
    [ "$SESSION_SECS" -lt 0 ] && SESSION_SECS=0
    TOTAL_SECS=$(( ACCUMULATED_SECONDS + SESSION_SECS ))

    if [ "$TOTAL_SECS" -ne "$LAST_DISPLAYED_SEC" ]; then
        LAST_DISPLAYED_SEC=$TOTAL_SECS
        printf "\r ${C_CYAN}Elapsed:${C_RESET} %s  ${C_DIM}[Session: %s]${C_RESET}  ${C_YELLOW}(CTRL+D to stop)${C_RESET}\033[K" \
            "$(format_time "$TOTAL_SECS")" \
            "$(format_time "$SESSION_SECS")"
    fi

    # Auto-save every 300 seconds as safety net
    if [ $(( NOW - LAST_AUTOSAVE )) -ge 300 ]; then
        save_time "$TOTAL_SECS"
        LAST_AUTOSAVE=$NOW
    fi

    # Read from stdin with 0.2s timeout
    # When EOF (CTRL+D) is pressed, read returns exit code 1 (1 <= rc <= 128)
    read -t 0.2 
    rc=$?

    if [ "$rc" -gt 0 ] && [ "$rc" -le 128 ]; then
        break
    fi
done

exit 0
