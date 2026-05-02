#!/usr/bin/env bash
# Shared bats test setup: isolated cache dir, PATH override, clean MOCK_* env.

PROJECT_ROOT="$(cd "${BATS_TEST_DIRNAME:-$(dirname "${BASH_SOURCE[0]}")}/.." && pwd)"
SCRIPTS_DIR="$PROJECT_ROOT/scripts"
STUBS_DIR="$PROJECT_ROOT/tests/stubs"

setup_test_env() {
    TMUX_USEFUL_CACHE_DIR="$(mktemp -d)"
    export TMUX_USEFUL_CACHE_DIR
    export PATH="$STUBS_DIR:$PATH"
    # tmux env var so tmux stub doesn't error if scripts run any extra checks.
    export TMUX="${TMUX:-/tmp/tmux-fake}"
    # Clear any MOCK_* leftover from a prior test in same shell.
    while IFS= read -r v; do unset "$v"; done < <(env | awk -F= '/^MOCK_/ {print $1}')
}

teardown_test_env() {
    [ -n "${TMUX_USEFUL_CACHE_DIR:-}" ] && [ -d "$TMUX_USEFUL_CACHE_DIR" ] && rm -rf "$TMUX_USEFUL_CACHE_DIR"
}

# Strip tmux #[...] format directives so assertions can match content alone.
strip_format() {
    sed -E 's/#\[[^]]*\]//g'
}
