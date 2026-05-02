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

@test "default_color_dim is WCAG-AA-passing" {
    run color_dim
    [ "$output" = "#7b8696" ]
}

@test "segment_enabled returns 0 by default" {
    run segment_enabled "anything"
    [ "$status" -eq 0 ]
}

@test "segment_enabled returns 1 when option set to off" {
    export MOCK_OPT_useful_foo_enabled=off
    run segment_enabled "foo"
    [ "$status" -eq 1 ]
}

@test "segment_enabled accepts off/false/0/no" {
    for v in off false 0 no; do
        export MOCK_OPT_useful_foo_enabled="$v"
        run segment_enabled "foo"
        [ "$status" -eq 1 ] || { echo "value $v should disable, status=$status" >&2; return 1; }
    done
}

@test "useful_cache_dir respects @useful-cache-dir option" {
    export MOCK_OPT_useful_cache_dir="/tmp/explicit-override"
    mkdir -p /tmp/explicit-override
    run useful_cache_dir
    [ "$output" = "/tmp/explicit-override" ]
    rmdir /tmp/explicit-override 2>/dev/null || true
}
