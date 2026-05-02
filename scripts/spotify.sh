#!/usr/bin/env bash
# Spotify now-playing for tmux status bar — slides through the full title
# once on each track change, then settles to a truncated view.
# macOS only. The slide is event-driven (track change) so motion never
# becomes ambient/distracting.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$DIR/helpers.sh"

CACHE_DIR_BASE="${TMUX_USEFUL_CACHE_DIR:-/tmp}"
TRACK_CACHE="$CACHE_DIR_BASE/tmux-useful-spotify-track-cache"
STATE_FILE="$CACHE_DIR_BASE/tmux-useful-spotify-state"

MAX_LEN=$(get_tmux_option "@useful-spotify-max-len" 30)
ICON=$(get_tmux_option "@useful-spotify-icon" "")
SEPARATOR=$(get_tmux_option "@useful-spotify-separator" " · ")
ACCENT=$(color_accent)
SCROLL_ENABLED=$(get_tmux_option "@useful-spotify-scroll" "on")
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
    track_cache_age=$(( now - $(stat -f %m "$TRACK_CACHE") ))
    if [ "$track_cache_age" -lt 5 ]; then
        track=$(cat "$TRACK_CACHE")
        need_fetch=0
    fi
fi

if [ "$need_fetch" -eq 1 ]; then
    if pgrep -x Spotify >/dev/null 2>&1; then
        track=$(osascript 2>/dev/null <<EOF
tell application "Spotify"
    if player state is playing then
        return (artist of current track) & "${SEPARATOR}" & (name of current track)
    end if
end tell
EOF
)
    fi
    printf "%s" "$track" >"$TRACK_CACHE"
fi

if [ -z "$track" ]; then
    rm -f "$STATE_FILE"
    exit 0
fi

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
       && [ "${#track}" -gt "$MAX_LEN" ]; then
        (
            window_end=$(( now + DWELL + SLIDE_DURATION + DWELL + 1 ))
            while [ "$(date +%s)" -lt "$window_end" ]; do
                sleep 1
                tmux refresh-client -S 2>/dev/null
            done
        ) </dev/null >/dev/null 2>&1 &
        disown $!
    fi
fi

# --------------------------------------------------- compute display window
len="${#track}"
elapsed=$(( now - cycle_start ))
[ "$SLIDE_DURATION" -lt 1 ] && SLIDE_DURATION=1
slide_end=$(( DWELL + SLIDE_DURATION ))
end_dwell=$(( DWELL + SLIDE_DURATION + DWELL ))

if [ "$len" -le "$MAX_LEN" ]; then
    display="$track"
elif [ "$SCROLL_ENABLED" != "on" ]; then
    display="${track:0:$((MAX_LEN - 1))}…"
elif [ "$elapsed" -lt "$DWELL" ]; then
    display="${track:0:$((MAX_LEN - 1))}…"
elif [ "$elapsed" -lt "$slide_end" ]; then
    overflow=$(( len - MAX_LEN ))
    progress=$(( elapsed - DWELL ))
    offset=$(( progress * overflow / SLIDE_DURATION ))
    [ "$offset" -lt 0 ] && offset=0
    [ "$offset" -gt "$overflow" ] && offset="$overflow"

    if [ "$offset" -eq 0 ]; then
        display="${track:0:$((MAX_LEN - 1))}…"
    elif [ "$offset" -ge "$overflow" ]; then
        display="…${track: -$((MAX_LEN - 1))}"
    else
        display="…${track:$((offset + 1)):$((MAX_LEN - 2))}…"
    fi
elif [ "$elapsed" -lt "$end_dwell" ]; then
    display="…${track: -$((MAX_LEN - 1))}"
else
    display="${track:0:$((MAX_LEN - 1))}…"
fi

printf "#[fg=%s] %s %s #[fg=default]" "$ACCENT" "$ICON" "$display"
