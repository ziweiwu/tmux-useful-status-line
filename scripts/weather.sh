#!/usr/bin/env bash
# Weather via wttr.in — refreshes every 15 min, dims when stale > 1hr.
# Configurable location; empty string falls back to wttr.in's geo-IP lookup.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Guarded so bin/useful-status can source helpers once and then source all
# six segments without each re-running the config snapshot.
# shellcheck source=helpers.sh
[ -n "${USEFUL_HELPERS_LOADED:-}" ] || source "$DIR/helpers.sh"

# The body lives in a function so the six segments can share one process.
# Deliberately not re-indented: it keeps this diff reviewable and leaves
# column-0 heredoc terminators intact.
useful_segment_weather() {
segment_enabled "weather" || return 0

REFRESH_SEC=$(useful_int_option "@useful-weather-refresh" 900)
STALE_SEC=$(useful_int_option "@useful-weather-stale" 3600)
LOCATION=$(get_tmux_option "@useful-weather-location" "")
FORMAT=$(get_tmux_option "@useful-weather-format" "%c+%t")
# wttr.in answers with whatever it feels like: an error page, a captive-portal
# interception, or a rich custom %format. Every other segment budgets its cells;
# this one used to emit the response verbatim, so a 2KB body became a 2KB
# status line.
MAX_LEN=$(useful_int_option "@useful-weather-max-len" 24)
# See @useful-timeout in helpers.sh. curl gets the same guard every other
# external command has: --max-time bounds the transfer, but it is curl's own
# knob, so it neither honours @useful-timeout nor contributes to the whole-run
# @useful-timeout-total ceiling that exists to bound ten wedged calls at once.
TIMEOUT=$(useful_int_option "@useful-timeout" 3)
DIM=$(color_dim)

# Namespace the cache by location+format so changing config yields a fresh fetch
# instead of returning stale data from a different city.
cache_key=$(useful_hash "$(printf "%s|%s" "$LOCATION" "$FORMAT")")
CACHE_FILE="$(useful_cache_dir)/weather-${cache_key}"

# A failed fetch writes nothing, so without a separate marker `needs_refresh`
# stays 1 forever and every single refresh re-attempts a blocking network call.
# Offline, that is a 5-second stall on every status tick — and on every shell
# prompt, for anyone following the README's RPROMPT recipe. Stamp the attempt
# so failures are rate-limited the way successes already are.
# Dot-prefixed and keyed separately so that `weather-*` in the cache dir keeps
# meaning "cached weather data" — for tests, and for anyone poking at the dir.
ATTEMPT_FILE="$(useful_cache_dir)/.weather-${cache_key}.try"
RETRY_SEC=60
[ "$RETRY_SEC" -gt "$REFRESH_SEC" ] && RETRY_SEC="$REFRESH_SEC"

now=$(date +%s)

# Age of $1 in seconds, into $age; non-zero if it cannot be determined.
#
# `$(( now - $(file_mtime f) ))` inlined is a trap: file_mtime prints NOTHING
# when the stat fails — the file was removed between the -f test and the call,
# or it sits on a filesystem stat cannot read — and bash then reports
# "syntax error: operand expected" for the empty operand and leaves the
# variable unset. cache_check already guards this with an emptiness test; these
# two call sites did not, and silently lost the stale "~" marker when it fired.
weather_age() {
    local mtime
    mtime=$(file_mtime "$1")
    case "$mtime" in
        ''|*[!0-9]*) return 1 ;;
    esac
    age=$(( now - mtime ))
    # A negative age means a future mtime — clock skew or a planted file. Treat
    # it as stale rather than as permanently fresh (see cache_check).
    [ "$age" -ge 0 ]
}

needs_refresh=1
if [ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ]; then
    weather_age "$CACHE_FILE" && [ "$age" -lt "$REFRESH_SEC" ] && needs_refresh=0
fi
if [ "$needs_refresh" -eq 1 ] && [ -f "$ATTEMPT_FILE" ]; then
    weather_age "$ATTEMPT_FILE" && [ "$age" -lt "$RETRY_SEC" ] && needs_refresh=0
fi

if [ "$needs_refresh" -eq 1 ]; then
    # Stamped BEFORE the call, so a hang or a kill still backs off.
    : >"$ATTEMPT_FILE"
    # Encode URL-breaking chars in the user-controlled location. wttr.in
    # accepts raw UTF-8 in the path, so we don't need full %XX encoding —
    # just escape the chars that change URL semantics (#, ?, &, space).
    loc_enc="$LOCATION"
    loc_enc="${loc_enc//\%/%25}"   # must come first
    loc_enc="${loc_enc//\#/%23}"
    loc_enc="${loc_enc//\?/%3F}"
    loc_enc="${loc_enc//&/%26}"
    loc_enc="${loc_enc// /%20}"
    # Bound the RESPONSE, not just the time it may take to arrive.
    #
    # USEFUL_MAX_CELLS bounds what gets DISPLAYED, and that was mistaken for a
    # bound on what gets stored. It is not: the raw body went into the cache
    # verbatim and was re-read with `cat` on every refresh for the whole
    # REFRESH_SEC. Measured, with a captive-portal splash of the kind these caps
    # exist for: a 2MB body cost 0.30s of CPU per status tick, an 8MB body
    # 1.07s — and only 0.2s of that was the read, the rest being the O(length)
    # slice inside useful_window. The driver runs six segments serially, so that
    # is the whole status line, every tick, for fifteen minutes.
    #
    # --max-filesize rejects an oversized body up front when the server declares
    # a length; `head -c` is what actually holds the line when it does not (a
    # chunked response declares nothing). 8192 bytes is far more than any
    # format string can legitimately produce and still nothing bash minds
    # slicing. `head` closing the pipe early also cuts the transfer short.
    fresh=$(useful_timeout "$TIMEOUT" curl -s --max-time 5 --max-filesize 65536 \
            "wttr.in/${loc_enc}?format=${FORMAT}" 2>/dev/null \
        | head -c 8192 | tr -d '+' | sed 's/  */ /g')
    if [ -n "$fresh" ] && ! echo "$fresh" | grep -qiE 'unknown|error|sorry|not found|^[[:space:]]*$'; then
        echo "$fresh" > "$CACHE_FILE"
    fi
fi

[ -f "$CACHE_FILE" ] && [ -s "$CACHE_FILE" ] || return 0

# An unreadable mtime here must mark the data as SUSPECT, not as fresh: the
# whole point of the marker is that the reader can tell old data from new.
marker_stale=0
weather_age "$CACHE_FILE" || marker_stale=1
text=$(cat "$CACHE_FILE")
# Weather is metadata, not status — render in dim by default so it doesn't
# compete with status colors. Stale (>1hr) data prepends a "~" — a font-
# agnostic, screen-reader-friendly cue that the data may be old. (Italics in
# monospace fonts often render identically to regular and don't survive
# screen readers, so we avoid relying on them.)
marker=""
if [ "$marker_stale" -eq 1 ] || [ "$age" -gt "$STALE_SEC" ]; then
    marker="~"
fi
# The marker is charged against the budget, not added on top of it.
budget="$MAX_LEN"
[ -n "$marker" ] && budget=$(( MAX_LEN - 1 ))
[ "$budget" -lt 1 ] && budget=1
useful_truncate "$text" "$budget"
printf " #[fg=%s]%s%s#[fg=default]" "$DIM" "$marker" "$(useful_escape "$USEFUL_TRUNC")"
}

# tmux calls this script directly via #(...); the driver sources it instead.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    useful_segment_weather
fi
