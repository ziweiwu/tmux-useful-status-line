#!/usr/bin/env bash
# Spotify now-playing for tmux status bar.
# Cached 5s. No-op when Spotify isn't running. macOS only.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$DIR/helpers.sh"

CACHE_FILE="${TMUX_USEFUL_CACHE_DIR:-/tmp}/tmux-useful-spotify-cache"
cache_check "$CACHE_FILE" 5 && exit 0

MAX_LEN=$(get_tmux_option "@useful-spotify-max-len" 30)
ICON=$(get_tmux_option "@useful-spotify-icon" "")
SEPARATOR=$(get_tmux_option "@useful-spotify-separator" " · ")
ACCENT=$(color_accent)

if ! pgrep -x Spotify >/dev/null 2>&1; then
    : > "$CACHE_FILE"
    exit 0
fi

track=$(osascript 2>/dev/null <<EOF
tell application "Spotify"
    if player state is playing then
        return (artist of current track) & "${SEPARATOR}" & (name of current track)
    end if
end tell
EOF
)

if [ -n "$track" ]; then
    if [ "${#track}" -gt "$MAX_LEN" ]; then
        track="${track:0:MAX_LEN}…"
    fi
    printf "#[fg=%s] %s %s #[fg=default]" "$ACCENT" "$ICON" "$track" | tee "$CACHE_FILE"
else
    : > "$CACHE_FILE"
fi
