#!/usr/bin/env bash
# Weather via wttr.in — refreshes every 15 min, dims when stale > 1hr.
# Configurable location; empty string falls back to wttr.in's geo-IP lookup.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$DIR/helpers.sh"

segment_enabled "weather" || exit 0

REFRESH_SEC=$(get_tmux_option "@useful-weather-refresh" 900)
STALE_SEC=$(get_tmux_option "@useful-weather-stale" 3600)
LOCATION=$(get_tmux_option "@useful-weather-location" "")
FORMAT=$(get_tmux_option "@useful-weather-format" "%c+%t")
DIM=$(color_dim)

# Namespace the cache by location+format so changing config yields a fresh fetch
# instead of returning stale data from a different city.
cache_key=$(printf "%s|%s" "$LOCATION" "$FORMAT" | shasum | cut -c1-8)
CACHE_FILE="$(useful_cache_dir)/weather-${cache_key}"

now=$(date +%s)
needs_refresh=1
if [ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ]; then
    cache_age=$(( now - $(file_mtime "$CACHE_FILE") ))
    [ "$cache_age" -lt "$REFRESH_SEC" ] && needs_refresh=0
fi

if [ "$needs_refresh" -eq 1 ]; then
    # Encode URL-breaking chars in the user-controlled location. wttr.in
    # accepts raw UTF-8 in the path, so we don't need full %XX encoding —
    # just escape the chars that change URL semantics (#, ?, &, space).
    loc_enc="$LOCATION"
    loc_enc="${loc_enc//\%/%25}"   # must come first
    loc_enc="${loc_enc//\#/%23}"
    loc_enc="${loc_enc//\?/%3F}"
    loc_enc="${loc_enc//&/%26}"
    loc_enc="${loc_enc// /%20}"
    fresh=$(curl -s --max-time 5 "wttr.in/${loc_enc}?format=${FORMAT}" 2>/dev/null \
        | tr -d '+' | sed 's/  */ /g')
    if [ -n "$fresh" ] && ! echo "$fresh" | grep -qiE 'unknown|error|sorry|not found|^[[:space:]]*$'; then
        echo "$fresh" > "$CACHE_FILE"
    fi
fi

[ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ] || exit 0

cache_age=$(( now - $(file_mtime "$CACHE_FILE") ))
text=$(cat "$CACHE_FILE")
# Weather is metadata, not status — render in dim by default so it doesn't
# compete with status colors. Stale (>1hr) data prepends a "~" — a font-
# agnostic, screen-reader-friendly cue that the data may be old. (Italics in
# monospace fonts often render identically to regular and don't survive
# screen readers, so we avoid relying on them.)
if [ "$cache_age" -gt "$STALE_SEC" ]; then
    printf " #[fg=%s]~%s#[fg=default]" "$DIM" "$text"
else
    printf " #[fg=%s]%s#[fg=default]" "$DIM" "$text"
fi
