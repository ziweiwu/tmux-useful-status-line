#!/usr/bin/env bash
# Spotify now-playing for tmux status bar — slides through the full title
# once on each track change, then settles to a truncated view.
# macOS only. The slide is event-driven (track change) so motion never
# becomes ambient/distracting.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Guarded so bin/useful-status can source helpers once and then source all
# six segments without each re-running the config snapshot.
# shellcheck source=helpers.sh
[ -n "${USEFUL_HELPERS_LOADED:-}" ] || source "$DIR/helpers.sh"

# The body lives in a function so the six segments can share one process.
# Deliberately not re-indented: it keeps this diff reviewable and leaves
# column-0 heredoc terminators intact.
useful_segment_spotify() {
segment_enabled "spotify" || return 0
is_darwin || return 0

CACHE_DIR_BASE="$(useful_cache_dir)"
TRACK_CACHE="$CACHE_DIR_BASE/spotify-track"
STATE_FILE="$CACHE_DIR_BASE/spotify-state"
WATCHDOG_PID_FILE="$CACHE_DIR_BASE/spotify-watchdog.pid"

MAX_LEN=$(get_tmux_option "@useful-spotify-max-len" 30)
ICON=$(get_tmux_option "@useful-spotify-icon" "")
SEPARATOR=$(get_tmux_option "@useful-spotify-separator" " · ")
ACCENT=$(color_accent)
SCROLL_ENABLED=$(get_tmux_option "@useful-spotify-scroll" "on")
# Honor REDUCED_MOTION (CSS-equivalent) and TMUX_USEFUL_REDUCED_MOTION as a
# global motion-sensitive escape hatch. Either being set forces scroll off.
if [ -n "${REDUCED_MOTION:-}" ] || [ -n "${TMUX_USEFUL_REDUCED_MOTION:-}" ]; then
    SCROLL_ENABLED="off"
fi
DWELL=$(get_tmux_option "@useful-spotify-scroll-dwell" 2)
SLIDE_DURATION=$(get_tmux_option "@useful-spotify-scroll-duration" 8)

# Tests inject TMUX_USEFUL_NOW to control elapsed time deterministically and
# TMUX_USEFUL_NO_WATCHDOG=1 to suppress the background refresher.
now="${TMUX_USEFUL_NOW:-$(date +%s)}"

# ------------------------------------------------------------------ track lookup
# osascript is the slow path; cache its result for 5s so we only ask Spotify
# at human-perception timescale, not on every status refresh.
track=""
need_fetch=1
if [ -f "$TRACK_CACHE" ]; then
    track_cache_age=$(( now - $(file_mtime "$TRACK_CACHE") ))
    if [ "$track_cache_age" -lt 5 ]; then
        track=$(cat "$TRACK_CACHE")
        need_fetch=0
    fi
fi
unset track_cache_age

if [ "$need_fetch" -eq 1 ]; then
    if pgrep -x Spotify >/dev/null 2>&1; then
        # Pass SEPARATOR as an argument (treated as data) instead of
        # interpolating into the AppleScript source — prevents injection
        # if the user's @useful-spotify-separator contains AppleScript
        # syntax like `" & (do shell script "...") & "`.
        track=$(osascript - "$SEPARATOR" 2>/dev/null <<'EOF'
on run argv
    set sep to item 1 of argv
    tell application "Spotify"
        if player state is playing then
            return (artist of current track) & sep & (name of current track)
        end if
    end tell
end run
EOF
)
    fi
    printf "%s" "$track" >"$TRACK_CACHE"
fi

if [ -z "$track" ]; then
    # Preserve STATE_FILE so resuming the same track later doesn't replay the
    # full slide animation. Just emit nothing for this tick.
    return 0
fi

# Everything below budgets in terminal CELLS, not characters. A Japanese title
# of 31 characters occupies 53 cells: measured in characters it looks like it
# overflows a 30-cell budget by one, so the slide would nudge a single glyph
# while the bar ran 23 cells over.
useful_display_width "$track"
track_cells=$USEFUL_WIDTH

# ----------------------------------------------------------- detect track change
prev_track=""
cycle_start="$now"
if [ -f "$STATE_FILE" ]; then
    IFS='|' read -r prev_track cycle_start <"$STATE_FILE"
fi

if [ "$track" != "$prev_track" ]; then
    cycle_start="$now"
    printf "%s|%s" "$track" "$cycle_start" >"$STATE_FILE"

    # Only spawn the watchdog when the title actually overflows AND scrolling
    # is enabled. Otherwise the slide is meaningless and motion is wasted.
    if [ -z "${TMUX_USEFUL_NO_WATCHDOG:-}" ] \
       && [ "$SCROLL_ENABLED" = "on" ] \
       && [ "$track_cells" -gt "$MAX_LEN" ]; then
        # Kill any leftover watchdog from a previous (now-stale) cycle so we
        # don't accumulate refreshers when tracks change rapidly.
        if [ -f "$WATCHDOG_PID_FILE" ]; then
            old_pid=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null)
            if [ -n "$old_pid" ] && kill -0 "$old_pid" 2>/dev/null; then
                # Be cautious: only kill if comm looks like our shell watchdog.
                comm=$(ps -p "$old_pid" -o comm= 2>/dev/null)
                case "$comm" in
                    *bash*|*sh*|*sleep*) kill "$old_pid" 2>/dev/null ;;
                esac
            fi
        fi

        (
            window_end=$(( now + DWELL + SLIDE_DURATION + DWELL + 1 ))
            while [ "$(date +%s)" -lt "$window_end" ]; do
                sleep 1
                useful_request_redraw
            done
        ) </dev/null >/dev/null 2>&1 &
        new_pid=$!
        echo "$new_pid" >"$WATCHDOG_PID_FILE"
        disown "$new_pid"
    fi
fi

# --------------------------------------------------- compute display window
elapsed=$(( now - cycle_start ))
[ "$SLIDE_DURATION" -lt 1 ] && SLIDE_DURATION=1
slide_end=$(( DWELL + SLIDE_DURATION ))
end_dwell=$(( DWELL + SLIDE_DURATION + DWELL ))

# The travel distance reserves one cell for the leading ellipsis, so the final
# frame lands flush against the end of the title instead of one cell short.
overflow=$(( track_cells - MAX_LEN + 1 ))
[ "$overflow" -lt 0 ] && overflow=0

# head window: content + trailing ellipsis, both inside MAX_LEN cells.
window_head() { useful_window "$track" 0 $(( MAX_LEN - 1 )); display="${USEFUL_WINDOW}…"; }
# tail window: leading ellipsis + the last MAX_LEN-1 cells.
window_tail() { useful_window "$track" "$overflow" $(( MAX_LEN - 1 )); display="…$USEFUL_WINDOW"; }

if [ "$track_cells" -le "$MAX_LEN" ]; then
    display="$track"
elif [ "$SCROLL_ENABLED" != "on" ]; then
    window_head
elif [ "$elapsed" -lt "$DWELL" ]; then
    window_head
elif [ "$elapsed" -lt "$slide_end" ]; then
    progress=$(( elapsed - DWELL ))
    offset=$(( progress * overflow / SLIDE_DURATION ))
    [ "$offset" -lt 0 ] && offset=0
    [ "$offset" -gt "$overflow" ] && offset="$overflow"

    if [ "$offset" -eq 0 ]; then
        window_head
    elif [ "$offset" -ge "$overflow" ]; then
        window_tail
    else
        useful_window "$track" "$offset" $(( MAX_LEN - 2 ))
        display="…${USEFUL_WINDOW}…"
    fi
elif [ "$elapsed" -lt "$end_dwell" ]; then
    window_tail
else
    window_head
fi

printf " #[fg=%s]%s %s#[fg=default]" "$ACCENT" "$ICON" "$display"
}

# tmux calls this script directly via #(...); the driver sources it instead.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    useful_segment_spotify
fi
