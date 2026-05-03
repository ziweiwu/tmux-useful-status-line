#!/usr/bin/env bats
# Tests for scripts/git.sh

load 'test_helpers'

setup() {
    setup_test_env
    REPO_DIR="$TMUX_USEFUL_CACHE_DIR/repo"
    mkdir -p "$REPO_DIR"
    git -C "$REPO_DIR" init -q -b main
    git -C "$REPO_DIR" config user.email "t@t" && git -C "$REPO_DIR" config user.name t
    git -C "$REPO_DIR" commit --allow-empty -q -m "init"
    export TMUX_PANE_CURRENT_PATH="$REPO_DIR"
}

teardown() {
    teardown_test_env
}

run_git() {
    run "$SCRIPTS_DIR/git.sh"
}

@test "outside a repo → empty" {
    export TMUX_PANE_CURRENT_PATH="$TMUX_USEFUL_CACHE_DIR"
    run_git
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "clean repo → branch in dim color, no dirty mark" {
    run_git
    [ "$status" -eq 0 ]
    [[ "$output" == *"main"* ]]
    [[ "$output" != *"main*"* ]]
    [[ "$output" == *"#[fg=#7b8696]"* ]]
}

@test "dirty repo → warn color and dirty mark" {
    echo "untracked" >"$REPO_DIR/file"
    run_git
    [[ "$output" == *"main*"* ]]
    [[ "$output" == *"#[fg=#ebcb8b]"* ]]
}

@test "long branch name truncates with ellipsis" {
    git -C "$REPO_DIR" checkout -q -b a-very-very-very-long-feature-branch-name
    run_git
    [[ "$output" == *"…"* ]]
}

@test "detached HEAD shows short SHA" {
    sha=$(git -C "$REPO_DIR" rev-parse --short HEAD)
    git -C "$REPO_DIR" checkout -q --detach HEAD
    run_git
    [[ "$output" == *"@${sha}"* ]]
}

@test "custom dirty mark respected" {
    echo "x" >"$REPO_DIR/x"
    export MOCK_OPT_useful_git_dirty_mark="±"
    run_git
    [[ "$output" == *"main±"* ]]
}

@test "git-skip-untracked=on ignores untracked files" {
    echo "untracked" >"$REPO_DIR/file"
    export MOCK_OPT_useful_git_skip_untracked=on
    run_git
    [[ "$output" != *"main*"* ]]
    [[ "$output" == *"main"* ]]
}

@test "git-skip-untracked=on still flags staged changes as dirty" {
    git -C "$REPO_DIR" commit --allow-empty -q -m "second" 2>/dev/null
    echo "tracked" >"$REPO_DIR/tracked"
    git -C "$REPO_DIR" add tracked
    export MOCK_OPT_useful_git_skip_untracked=on
    run_git
    [[ "$output" == *"main*"* ]]
}

@test "segment disabled → empty even in a dirty repo" {
    echo "x" >"$REPO_DIR/x"
    export MOCK_OPT_useful_git_enabled=off
    run_git
    [ "$output" = "" ]
}
