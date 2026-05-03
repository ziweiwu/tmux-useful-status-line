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
    touch_ago "$file" 100
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

@test "file_mtime returns mtime of an existing file" {
    file="$TMUX_USEFUL_CACHE_DIR/test_mtime"
    touch "$file"
    run file_mtime "$file"
    [ "$status" -eq 0 ]
    [ -n "$output" ]
    [ "$output" -gt 0 ]
}

@test "file_mtime returns nothing for missing file" {
    run file_mtime "$TMUX_USEFUL_CACHE_DIR/nonexistent"
    [ "$output" = "" ]
}

@test "is_darwin returns 0 on macOS" {
    if [ "$(uname -s)" = "Darwin" ]; then
        run is_darwin
        [ "$status" -eq 0 ]
    else
        skip "not on macOS"
    fi
}

@test "theme=catppuccin sets palette defaults" {
    export MOCK_OPT_useful_theme=catppuccin
    # Re-source helpers so the case statement at module-load time runs again
    # against the new option value.
    source "$SCRIPTS_DIR/helpers.sh"
    run color_ok
    [ "$output" = "#a6e3a1" ]
    run color_dim
    [ "$output" = "#9399b2" ]
}

@test "theme=gruvbox sets palette defaults" {
    export MOCK_OPT_useful_theme=gruvbox
    source "$SCRIPTS_DIR/helpers.sh"
    run color_warn
    [ "$output" = "#fabd2f" ]
}

@test "theme=rose-pine sets palette defaults" {
    export MOCK_OPT_useful_theme=rose-pine
    source "$SCRIPTS_DIR/helpers.sh"
    run color_accent
    [ "$output" = "#c4a7e7" ]
}

@test "explicit @useful-color-ok overrides the theme preset" {
    export MOCK_OPT_useful_theme=catppuccin
    export MOCK_OPT_useful_color_ok="#ff0000"
    source "$SCRIPTS_DIR/helpers.sh"
    run color_ok
    [ "$output" = "#ff0000" ]
}

@test "unknown theme falls through to Nord defaults" {
    export MOCK_OPT_useful_theme=does-not-exist
    source "$SCRIPTS_DIR/helpers.sh"
    run color_ok
    [ "$output" = "#a3be8c" ]
}

@test "theme=tokyo-night sets palette" {
    export MOCK_OPT_useful_theme=tokyo-night
    source "$SCRIPTS_DIR/helpers.sh"
    run color_ok
    [ "$output" = "#9ece6a" ]
    run color_accent
    [ "$output" = "#bb9af7" ]
}

@test "theme=dracula sets palette" {
    export MOCK_OPT_useful_theme=dracula
    source "$SCRIPTS_DIR/helpers.sh"
    run color_crit
    [ "$output" = "#ff5555" ]
}

@test "theme=onedark sets palette" {
    export MOCK_OPT_useful_theme=onedark
    source "$SCRIPTS_DIR/helpers.sh"
    run color_ok
    [ "$output" = "#98c379" ]
}

@test "theme=catppuccin-latte sets palette tuned for light bg" {
    export MOCK_OPT_useful_theme=catppuccin-latte
    source "$SCRIPTS_DIR/helpers.sh"
    run color_ok
    [ "$output" = "#40a02b" ]
    # Latte's dim must darken (against light bg), not lighten.
    run color_dim
    [ "$output" = "#6c6f85" ]
}

@test "theme=dark:X,light:Y resolves to dark variant when light env unset" {
    # In tests, COLORFGBG isn't set, so the Linux fallback defaults to 'dark'.
    export TMUX_USEFUL_OS_OVERRIDE=Linux
    export MOCK_OPT_useful_theme="dark:dracula,light:catppuccin-latte"
    rm -f "${TMPDIR:-/tmp}/tmux-useful-appearance"
    source "$SCRIPTS_DIR/helpers.sh"
    run color_crit
    [ "$output" = "#ff5555" ]   # dracula
}

@test "theme=dark:X,light:Y resolves to light variant under COLORFGBG light hint" {
    export TMUX_USEFUL_OS_OVERRIDE=Linux
    export COLORFGBG="0;15"   # bg index 15 = light
    export MOCK_OPT_useful_theme="dark:dracula,light:catppuccin-latte"
    rm -f "${TMPDIR:-/tmp}/tmux-useful-appearance"
    source "$SCRIPTS_DIR/helpers.sh"
    run color_ok
    [ "$output" = "#40a02b" ]   # catppuccin-latte
}

@test "useful_cache_dir respects @useful-cache-dir option" {
    export MOCK_OPT_useful_cache_dir="/tmp/explicit-override"
    mkdir -p /tmp/explicit-override
    run useful_cache_dir
    [ "$output" = "/tmp/explicit-override" ]
    rmdir /tmp/explicit-override 2>/dev/null || true
}
