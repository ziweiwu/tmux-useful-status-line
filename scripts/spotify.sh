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

MAX_LEN=$(useful_int_option "@useful-spotify-max-len" 30)
# An icon set to "" is a supported way to ask for no icon. Carry the separating
# space ON the icon so the empty case collapses cleanly instead of emitting the
# doubled leading space that "%s %s" would produce.
ICON=$(useful_icon_option "@useful-spotify-icon" "")
SEPARATOR=$(get_tmux_option "@useful-spotify-separator" " · ")
ACCENT=$(color_accent)
SCROLL_ENABLED=$(get_tmux_option "@useful-spotify-scroll" "on")
# Honor REDUCED_MOTION (CSS-equivalent) and TMUX_USEFUL_REDUCED_MOTION as a
# global motion-sensitive escape hatch. Either being set forces scroll off.
if [ -n "${REDUCED_MOTION:-}" ] || [ -n "${TMUX_USEFUL_REDUCED_MOTION:-}" ]; then
    SCROLL_ENABLED="off"
fi
DWELL=$(useful_int_option "@useful-spotify-scroll-dwell" 2)
SLIDE_DURATION=$(useful_int_option "@useful-spotify-scroll-duration" 8)
# See @useful-timeout in helpers.sh. AppleScript blocks on an unresponsive
# Spotify — including on the modal dialog it shows when it wants a login.
TIMEOUT=$(useful_int_option "@useful-timeout" 3)

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
    if useful_timeout "$TIMEOUT" pgrep -x Spotify >/dev/null 2>&1; then
        # Pass SEPARATOR as an argument (treated as data) instead of
        # interpolating into the AppleScript source — prevents injection
        # if the user's @useful-spotify-separator contains AppleScript
        # syntax like `" & (do shell script "...") & "`.
        track=$(useful_timeout "$TIMEOUT" osascript - "$SEPARATOR" 2>/dev/null <<'EOF'
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
# Bound the title before any cell arithmetic touches it. A track name is
# third-party metadata with no length limit behind it, and every measurement
# below — the width, the slide offsets, the windows — is linear in its length.
# USEFUL_MAX_CELLS is far wider than any status bar, so this changes nothing a
# user could see; it only stops a pathological title from being measured.
useful_truncate "$track" "$USEFUL_MAX_CELLS" ""
track="$USEFUL_TRUNC"

useful_display_width "$track"
track_cells=$USEFUL_WIDTH

# ----------------------------------------------------------- detect track change
prev_track=""
cycle_start="$now"
if [ -f "$STATE_FILE" ]; then
    # TIMESTAMP FIRST, track second — the order is the whole point.
    #
    # `read -r a b` gives the LAST variable the entire remainder of the line,
    # delimiters included. With the track written first, a title containing a
    # "|" — "Glory Box | Live at Roseland", and pipes in titles are common —
    # split as prev_track="Glory Box " and cycle_start=" Live at Roseland|1000".
    # prev_track then never equalled track, so the change branch below fired on
    # EVERY status refresh: the slide was pinned to frame 0 for the life of the
    # track, and the watchdog was killed and respawned once per tick instead of
    # once per track. A timestamp cannot contain a "|", so putting it first
    # makes the split exact whatever the title contains.
    IFS='|' read -r cycle_start prev_track <"$STATE_FILE"
    case "$cycle_start" in
        ''|*[!0-9]*) cycle_start="$now"; prev_track="" ;;
    esac
fi

if [ "$track" != "$prev_track" ]; then
    cycle_start="$now"
    printf "%s|%s" "$cycle_start" "$track" >"$STATE_FILE"

    # Only spawn the watchdog when the title actually overflows AND scrolling
    # is enabled. Otherwise the slide is meaningless and motion is wasted.
    if [ -z "${TMUX_USEFUL_NO_WATCHDOG:-}" ] \
       && [ "$SCROLL_ENABLED" = "on" ] \
       && [ "$track_cells" -gt "$MAX_LEN" ]; then
        # Kill any leftover watchdog from a previous (now-stale) cycle so we
        # don't accumulate refreshers when tracks change rapidly.
        #
        # The guard here is the PID FILE'S AGE, not the process name. A
        # watchdog lives at most `window_end - now` seconds and the file is
        # stamped when it is spawned, so past that the PID is certainly not
        # ours any more and the OS is free to have reused it. The old check —
        # `case $comm in *bash*|*sh*|*sleep*)` — was very nearly vacuous: it
        # matches zsh, fish, dash, ssh and sshd, so once a stale PID was
        # recycled we would SIGTERM a completely unrelated process, up to and
        # including the user's own login shell. Nothing ever removed the file,
        # so that window stayed open indefinitely.
        watchdog_life=$(( DWELL + SLIDE_DURATION + DWELL + 3 ))
        if [ -f "$WATCHDOG_PID_FILE" ]; then
            old_pid=$(cat "$WATCHDOG_PID_FILE" 2>/dev/null)
            pid_mtime=$(file_mtime "$WATCHDOG_PID_FILE")
            case "$pid_mtime" in ''|*[!0-9]*) pid_mtime=0 ;; esac
            pid_age=$(( now - pid_mtime ))
            case "$old_pid" in ''|*[!0-9]*) old_pid="" ;; esac
            if [ -n "$old_pid" ] \
               && [ "$pid_age" -ge 0 ] && [ "$pid_age" -lt "$watchdog_life" ] \
               && kill -0 "$old_pid" 2>/dev/null; then
                kill "$old_pid" 2>/dev/null
            fi
            # Whether or not it was still alive, the record is spent. Removing
            # it is what stops a recycled PID being read back later.
            rm -f "$WATCHDOG_PID_FILE" 2>/dev/null
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
    # Routed through useful_window even though it fits, for the same reason
    # useful_truncate is: the mark clamp lives there, and a title that MEASURES
    # eleven cells can still be four hundred characters of stacked diacritics.
    useful_window "$track" 0 "$MAX_LEN"
    display="$USEFUL_WINDOW"
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

# Track and artist are third-party metadata — anyone who can name a playlist
# entry can put "#[bg=red]" in it. Escaped for the same reason as git.sh.
printf " #[fg=%s]%s%s#[fg=default]" "$ACCENT" "$ICON" "$(useful_escape "$display")"
}

# tmux calls this script directly via #(...); the driver sources it instead.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    useful_segment_spotify
fi
