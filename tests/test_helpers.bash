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

# Portable "touch this file to N seconds ago" — BSD `touch -t` and `date -v`
# differ from GNU. This helper hides the difference for tests.
touch_ago() {
    local file="$1" seconds_ago="$2"
    local target_epoch=$(( $(date +%s) - seconds_ago ))
    if date -r 0 +%Y >/dev/null 2>&1; then
        # BSD date: -r EPOCH formats; -j -f for parsing. Use BSD touch -t.
        local stamp
        stamp=$(date -r "$target_epoch" +%Y%m%d%H%M.%S)
        touch -t "$stamp" "$file"
    else
        # GNU date and touch: -d accepts "@EPOCH"; touch -d accepts ISO-ish.
        touch -d "@$target_epoch" "$file"
    fi
}
