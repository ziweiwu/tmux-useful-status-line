#!/usr/bin/env bash
# Weather via wttr.in — refreshes every 15 min, dims when stale > 1hr.
# Configurable location; empty string falls back to wttr.in's geo-IP lookup.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$DIR/helpers.sh"

REFRESH_SEC=$(get_tmux_option "@useful-weather-refresh" 900)
STALE_SEC=$(get_tmux_option "@useful-weather-stale" 3600)
LOCATION=$(get_tmux_option "@useful-weather-location" "")
FORMAT=$(get_tmux_option "@useful-weather-format" "%c+%C+%t++💧%h++💨%w")
DIM=$(color_dim)

# Namespace the cache by location+format so changing config yields a fresh fetch
# instead of returning stale data from a different city.
cache_key=$(printf "%s|%s" "$LOCATION" "$FORMAT" | shasum | cut -c1-8)
CACHE_FILE="${TMUX_USEFUL_CACHE_DIR:-/tmp}/tmux-useful-weather-cache-${cache_key}"

now=$(date +%s)
needs_refresh=1
if [ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ]; then
    cache_age=$(( now - $(stat -f %m "$CACHE_FILE") ))
    [ "$cache_age" -lt "$REFRESH_SEC" ] && needs_refresh=0
fi

if [ "$needs_refresh" -eq 1 ]; then
    # URL-encode spaces in location.
    loc_enc="${LOCATION// /%20}"
    fresh=$(curl -s --max-time 5 "wttr.in/${loc_enc}?format=${FORMAT}" 2>/dev/null \
        | tr -d '+' | sed 's/  */ /g')
    if [ -n "$fresh" ] && ! echo "$fresh" | grep -qiE 'unknown|error|sorry|not found|^[[:space:]]*$'; then
        echo "$fresh" > "$CACHE_FILE"
    fi
fi

[ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ] || exit 0

cache_age=$(( now - $(stat -f %m "$CACHE_FILE") ))
text=$(cat "$CACHE_FILE")
if [ "$cache_age" -gt "$STALE_SEC" ]; then
    printf "#[fg=%s]%s#[fg=default]" "$DIM" "$text"
else
    printf "%s" "$text"
fi
