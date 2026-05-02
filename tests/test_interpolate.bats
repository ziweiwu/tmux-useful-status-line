#!/usr/bin/env bats
# Tests for useful-status-line.tmux (placeholder interpolation).

load 'test_helpers'

setup() {
    setup_test_env
    # Use a temp file to capture what `tmux set-option` would have written.
    export TMUX_TEST_OUT="$TMUX_USEFUL_CACHE_DIR/tmux_calls.txt"
    : >"$TMUX_TEST_OUT"
}

teardown() {
    teardown_test_env
}

# Override the tmux stub for these tests: we need to capture set-option calls
# and return a configurable show-option value.
write_tmux_stub() {
    local stub="$TMUX_USEFUL_CACHE_DIR/tmux"
    cat >"$stub" <<EOF
#!/usr/bin/env bash
if [ "\$1" = "show-option" ] && [ "\$2" = "-gqv" ]; then
    case "\$3" in
        status-left)  printf "%s" "\${MOCK_STATUS_LEFT:-}";;
        status-right) printf "%s" "\${MOCK_STATUS_RIGHT:-}";;
        *) printf "";;
    esac
    exit 0
fi
if [ "\$1" = "set-option" ] && [ "\$2" = "-gq" ]; then
    printf "SET %s=%s\n" "\$3" "\$4" >>"$TMUX_TEST_OUT"
    exit 0
fi
exit 0
EOF
    chmod +x "$stub"
    export PATH="$TMUX_USEFUL_CACHE_DIR:$PATH"
}

@test "spotify placeholder is replaced with shell-out call to spotify.sh" {
    write_tmux_stub
    export MOCK_STATUS_RIGHT="prefix #{useful_spotify} suffix"
    run "$PROJECT_ROOT/useful-status-line.tmux"
    [ "$status" -eq 0 ]
    grep -q "spotify.sh" "$TMUX_TEST_OUT"
    grep -q "prefix" "$TMUX_TEST_OUT"
    grep -q "suffix" "$TMUX_TEST_OUT"
}

@test "all four placeholders are replaced" {
    write_tmux_stub
    export MOCK_STATUS_RIGHT="#{useful_spotify}#{useful_system}#{useful_weather}#{useful_battery}"
    run "$PROJECT_ROOT/useful-status-line.tmux"
    grep -q "spotify.sh" "$TMUX_TEST_OUT"
    grep -q "system.sh" "$TMUX_TEST_OUT"
    grep -q "weather.sh" "$TMUX_TEST_OUT"
    grep -q "battery.sh" "$TMUX_TEST_OUT"
}

@test "status-left placeholders are also processed" {
    write_tmux_stub
    export MOCK_STATUS_LEFT="left #{useful_battery}"
    export MOCK_STATUS_RIGHT=""
    run "$PROJECT_ROOT/useful-status-line.tmux"
    grep -q "status-left" "$TMUX_TEST_OUT"
    grep -q "battery.sh" "$TMUX_TEST_OUT"
}

@test "options without placeholders are not modified" {
    write_tmux_stub
    export MOCK_STATUS_RIGHT="just plain text %H:%M"
    export MOCK_STATUS_LEFT=""
    run "$PROJECT_ROOT/useful-status-line.tmux"
    # Plugin should not call set-option for an unmodified option containing no placeholders;
    # but it does set-option unconditionally as long as value is non-empty. Verify the value
    # is preserved verbatim (no mangling).
    grep -F "just plain text %H:%M" "$TMUX_TEST_OUT"
}

@test "empty status-right is skipped (no set-option call)" {
    write_tmux_stub
    export MOCK_STATUS_RIGHT=""
    export MOCK_STATUS_LEFT=""
    run "$PROJECT_ROOT/useful-status-line.tmux"
    [ ! -s "$TMUX_TEST_OUT" ]
}
