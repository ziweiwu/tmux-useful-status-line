#!/usr/bin/env bats
# Tests for scripts/weather.sh

load 'test_helpers'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

run_weather() {
    run "$SCRIPTS_DIR/weather.sh"
}

@test "successful fetch returns curl output" {
    export MOCK_CURL_OUTPUT="☀️ Clear 20°C 💧40% 💨↗5km/h"
    run_weather
    [ "$status" -eq 0 ]
    [[ "$output" == *"Clear 20°C"* ]]
}

@test "'location not found' is filtered out" {
    export MOCK_CURL_OUTPUT="location not found: location not found"
    run_weather
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "'Unknown location' is filtered out" {
    export MOCK_CURL_OUTPUT="Unknown location; please try"
    run_weather
    [ "$output" = "" ]
}

@test "empty curl response → empty output" {
    export MOCK_CURL_OUTPUT=""
    run_weather
    [ "$output" = "" ]
}

@test "cache is reused on second call (curl not invoked again)" {
    export MOCK_CURL_OUTPUT="☀️ First"
    run_weather
    [[ "$output" == *"First"* ]]
    # Change the mock — cache should still return First.
    export MOCK_CURL_OUTPUT="☀️ Second"
    run_weather
    [[ "$output" == *"First"* ]]
}

@test "cache namespaced by location" {
    export MOCK_OPT_useful_weather_location="Tokyo"
    export MOCK_CURL_OUTPUT="☀️ Tokyo data"
    run_weather
    [[ "$output" == *"Tokyo data"* ]]

    # Switch location → different cache key, fresh fetch.
    export MOCK_OPT_useful_weather_location="London"
    export MOCK_CURL_OUTPUT="🌧 London data"
    run_weather
    [[ "$output" == *"London data"* ]]
}

@test "stale cache prepends '~' marker" {
    export MOCK_CURL_OUTPUT="☀️ Old"
    run_weather
    cache_file=$(ls "$TMUX_USEFUL_CACHE_DIR"/weather-*)
    # Backdate cache to 2 hours ago so it crosses default 1hr stale threshold.
    touch_ago "$cache_file" 7200
    # Force fetch attempt to fail (empty curl) so we fall back to the stale cached value.
    export MOCK_CURL_OUTPUT=""
    run_weather
    [[ "$output" == *"~"* ]]
    [[ "$output" == *"Old"* ]]
}

@test "fresh cache renders without stale marker" {
    export MOCK_CURL_OUTPUT="☀️ Fresh"
    run_weather
    [[ "$output" == *"Fresh"* ]]
    [[ "$output" != *"~☀️"* ]]
    [[ "$output" != *"~Fresh"* ]]
}

@test "URL-breaking chars in location are encoded" {
    # We can't intercept the curl URL directly with the simple stub, but
    # we *can* verify the script doesn't crash when special chars appear
    # and that the cache key is stable for a given location.
    export MOCK_OPT_useful_weather_location="Foo? & #Bar"
    export MOCK_CURL_OUTPUT="🌧 6°C"
    run_weather
    [[ "$output" == *"6°C"* ]]
    # Verify a cache file was actually written (i.e., script didn't error out).
    ls "$TMUX_USEFUL_CACHE_DIR"/weather-* >/dev/null
}

@test "configurable stale threshold respected (~ flips on)" {
    export MOCK_OPT_useful_weather_stale=1
    export MOCK_CURL_OUTPUT="☀️ Test"
    run_weather
    sleep 2
    cache_file=$(ls "$TMUX_USEFUL_CACHE_DIR"/weather-*)
    touch_ago "$cache_file" 5
    export MOCK_CURL_OUTPUT=""   # block refresh
    run_weather
    [[ "$output" == *"~"* ]]
}

@test "a failed fetch is rate-limited instead of retried every refresh" {
    # Nothing was written on failure, so needs_refresh stayed 1 forever and
    # every status tick paid for another blocking network call.
    export MOCK_CURL_OUTPUT=""
    run_weather
    [ -f "$TMUX_USEFUL_CACHE_DIR/.weather-"*".try" ]
}

@test "the retry marker does not masquerade as cached weather data" {
    export MOCK_CURL_OUTPUT=""
    run_weather
    run bash -c 'ls "$1"/weather-* 2>/dev/null | wc -l' _ "$TMUX_USEFUL_CACHE_DIR"
    [ "$(echo "$output" | tr -d ' ')" = "0" ]
}

@test "a successful fetch still refreshes on schedule" {
    export MOCK_CURL_OUTPUT="☀️ First"
    run_weather
    [[ "$output" == *"First"* ]]
    export MOCK_CURL_OUTPUT="🌧 Second"
    cache_file=$(ls "$TMUX_USEFUL_CACHE_DIR"/weather-*)
    touch_ago "$cache_file" 2000
    rm -f "$TMUX_USEFUL_CACHE_DIR"/.weather-*.try
    run_weather
    [[ "$output" == *"Second"* ]]
}

@test "an oversized response is truncated to the cell budget" {
    export MOCK_CURL_OUTPUT="$(printf 'X%.0s' $(seq 1 2000))"
    run_weather
    [ "$status" -eq 0 ]
    plain=$(printf "%s" "$output" | strip_format)
    [ "${#plain}" -lt 40 ]
}

@test "@useful-weather-max-len controls the budget" {
    export MOCK_CURL_OUTPUT="abcdefghijklmnopqrstuvwxyz"
    export MOCK_OPT_useful_weather_max_len=8
    run_weather
    plain=$(printf "%s" "$output" | strip_format)
    # one leading space + 8 cells
    [ "${#plain}" -le 9 ]
}

@test "tmux format syntax in a wttr.in response is escaped" {
    # The response is network-controlled: a captive portal or a compromised
    # endpoint could otherwise repaint the whole status bar.
    export MOCK_CURL_OUTPUT='#[bg=red]HACK'
    run_weather
    [[ "$output" == *'##[bg=red]'* ]]
}

@test "an oversized response body is bounded before it is cached" {
    # USEFUL_MAX_CELLS bounds what is DISPLAYED; it was mistaken for a bound on
    # what is STORED. The raw body went into the cache verbatim and was re-read
    # on every refresh for the whole REFRESH_SEC -- measured at 0.30s of CPU per
    # tick for a 2MB captive-portal splash, 1.07s for 8MB.
    export MOCK_CURL_OUTPUT="$(printf 'X%.0s' $(seq 1 60000))"
    run_weather
    cache=$(ls "$TMUX_USEFUL_CACHE_DIR"/weather-* 2>/dev/null | head -1)
    [ -n "$cache" ]
    [ "$(wc -c <"$cache")" -le 8200 ]
}

@test "the stale marker survives an unreadable mtime" {
    # `$(( now - $(file_mtime f) ))` inlined leaves the variable UNSET when the
    # stat fails, so the comparison silently dropped the "~".
    export MOCK_CURL_OUTPUT="☀️ 20°C"
    run_weather
    cache=$(ls "$TMUX_USEFUL_CACHE_DIR"/weather-* 2>/dev/null | head -1)
    [ -n "$cache" ]
    stub="$TMUX_USEFUL_CACHE_DIR/nostat"
    mkdir -p "$stub"
    printf '#!/bin/sh\nexit 1\n' >"$stub/stat"
    chmod +x "$stub/stat"
    export MOCK_CURL_OUTPUT=""
    run env PATH="$stub:$PATH" "$SCRIPTS_DIR/weather.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"~"* ]]
}

@test "curl runs under useful_timeout, not just its own --max-time" {
    # --max-time is curl's knob: it neither honours @useful-timeout nor counts
    # against the whole-run @useful-timeout-total ceiling.
    grep -q 'useful_timeout "\$TIMEOUT" curl' "$SCRIPTS_DIR/weather.sh"
}

@test "each location keeps its own cache entry without shasum on PATH" {
    # An empty cache key is a COLLIDING key: every location shared one entry.
    stub="$TMUX_USEFUL_CACHE_DIR/nohash"
    mkdir -p "$stub"
    for c in shasum sha1sum cksum; do
        printf '#!/bin/sh\nexit 127\n' >"$stub/$c"
        chmod +x "$stub/$c"
    done
    export MOCK_CURL_OUTPUT="☀️ Tokyo"
    MOCK_OPT_useful_weather_location=Tokyo \
        run env PATH="$stub:$PATH" "$SCRIPTS_DIR/weather.sh"
    export MOCK_CURL_OUTPUT="🌧 London"
    MOCK_OPT_useful_weather_location=London \
        run env PATH="$stub:$PATH" "$SCRIPTS_DIR/weather.sh"
    [ "$(ls "$TMUX_USEFUL_CACHE_DIR"/weather-* 2>/dev/null | wc -l)" -eq 2 ]
}
