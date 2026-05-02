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
    touch -t "$(date -v-2H +%Y%m%d%H%M.%S)" "$cache_file"
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

@test "configurable stale threshold respected (~ flips on)" {
    export MOCK_OPT_useful_weather_stale=1
    export MOCK_CURL_OUTPUT="☀️ Test"
    run_weather
    sleep 2
    cache_file=$(ls "$TMUX_USEFUL_CACHE_DIR"/weather-*)
    touch -t "$(date -v-5S +%Y%m%d%H%M.%S)" "$cache_file"
    export MOCK_CURL_OUTPUT=""   # block refresh
    run_weather
    [[ "$output" == *"~"* ]]
}
