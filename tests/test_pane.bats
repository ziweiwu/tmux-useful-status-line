#!/usr/bin/env bats
# Tests for scripts/pane.sh — active-pane command indicator.

load 'test_helpers'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

run_pane() {
    run "$SCRIPTS_DIR/pane.sh"
}

@test "default shell (zsh) → empty" {
    export MOCK_PANE_COMMAND=zsh
    run_pane
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "bash also hidden by default" {
    export MOCK_PANE_COMMAND=bash
    run_pane
    [ "$output" = "" ]
}

@test "vim shows up" {
    export MOCK_PANE_COMMAND=vim
    run_pane
    [[ "$output" == *"vim"* ]]
    [[ "$output" == *"#[fg=#7b8696]"* ]]
}

@test "claude shows up" {
    export MOCK_PANE_COMMAND=claude
    run_pane
    [[ "$output" == *"claude"* ]]
}

@test "long process name truncates" {
    export MOCK_PANE_COMMAND=an_extremely_long_process_name
    export MOCK_OPT_useful_pane_max_len=10
    run_pane
    [[ "$output" == *"…"* ]]
}

@test "empty pane command → empty output" {
    export MOCK_PANE_COMMAND=""
    run_pane
    [ "$output" = "" ]
}

@test "custom hide list overrides default" {
    export MOCK_PANE_COMMAND=vim
    export MOCK_OPT_useful_pane_hide="vim claude"
    run_pane
    [ "$output" = "" ]
}

@test "segment disabled → empty even when running interesting command" {
    export MOCK_PANE_COMMAND=vim
    export MOCK_OPT_useful_pane_enabled=off
    run_pane
    [ "$output" = "" ]
}

@test "version-string command hidden by default (e.g. Claude Code's 2.1.126)" {
    export MOCK_PANE_COMMAND=2.1.126
    run_pane
    [ "$output" = "" ]
}

@test "two-segment version string also hidden" {
    export MOCK_PANE_COMMAND=10.5
    run_pane
    [ "$output" = "" ]
}

@test "custom icon respected" {
    export MOCK_PANE_COMMAND=vim
    export MOCK_OPT_useful_pane_icon="◆"
    run_pane
    [[ "$output" == *"◆"* ]]
}
