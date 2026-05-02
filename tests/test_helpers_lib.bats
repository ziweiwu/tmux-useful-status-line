#!/usr/bin/env bats
# Tests for scripts/helpers.sh

load 'test_helpers'

setup() {
    setup_test_env
    # shellcheck source=../scripts/helpers.sh
    source "$SCRIPTS_DIR/helpers.sh"
}

teardown() {
    teardown_test_env
}

@test "get_tmux_option returns default when option unset" {
    run get_tmux_option "@useful-nonexistent" "fallback"
    [ "$status" -eq 0 ]
    [ "$output" = "fallback" ]
}

@test "get_tmux_option returns option value when set" {
    export MOCK_OPT_useful_mem_warn=42
    run get_tmux_option "@useful-mem-warn" "75"
    [ "$status" -eq 0 ]
    [ "$output" = "42" ]
}

@test "cache_check returns 1 when file missing" {
    run cache_check "$TMUX_USEFUL_CACHE_DIR/missing" 5
    [ "$status" -eq 1 ]
}

@test "cache_check returns 0 and prints contents when fresh" {
    file="$TMUX_USEFUL_CACHE_DIR/fresh"
    echo "hello" >"$file"
    run cache_check "$file" 5
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

@test "cache_check returns 1 when stale" {
    file="$TMUX_USEFUL_CACHE_DIR/stale"
    echo "old" >"$file"
    # Backdate the file by 100 seconds.
    touch -t "$(date -v-100S +%Y%m%d%H%M.%S)" "$file"
    run cache_check "$file" 5
    [ "$status" -eq 1 ]
}

@test "color_ok respects override" {
    export MOCK_OPT_useful_color_ok="#112233"
    run color_ok
    [ "$output" = "#112233" ]
}

@test "color_ok falls back to default" {
    run color_ok
    [ "$output" = "#a3be8c" ]
}
