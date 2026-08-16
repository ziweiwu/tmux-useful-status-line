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
    # Config is snapshotted once per process (see useful_config_load), so a
    # mock exported after setup()'s source needs an explicit re-read.
    useful_config_reset
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
    useful_config_reset
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
    useful_config_reset
    run useful_cache_dir
    [ "$output" = "/tmp/explicit-override" ]
    rmdir /tmp/explicit-override 2>/dev/null || true
}

# ------------------------------------------------------------- cache_check

@test "a cache file dated in the future is stale, not eternally fresh" {
    # A negative age passes any `age < max_age` test, which pinned the entry
    # as fresh forever. Clock skew and snapshot-restored VMs both produce it.
    cache_file="$TMUX_USEFUL_CACHE_DIR/future"
    echo "stale content" >"$cache_file"
    touch_ago "$cache_file" -3600     # one hour into the future
    run cache_check "$cache_file" 10
    [ "$status" -ne 0 ]
}

@test "a fresh cache file is still served" {
    cache_file="$TMUX_USEFUL_CACHE_DIR/fresh"
    echo "hello" >"$cache_file"
    run cache_check "$cache_file" 60
    [ "$status" -eq 0 ]
    [ "$output" = "hello" ]
}

# -------------------------------------------------------- useful_int_option

@test "a non-numeric option falls back to its default instead of erroring" {
    export MOCK_OPT_useful_mem_warn="seventy"
    useful_config_reset
    # Captured directly rather than with `run`: bats folds stderr into $output,
    # and the whole point of the diagnostic is that it is NOT on stdout.
    out=$(useful_int_option "@useful-mem-warn" 75 2>/dev/null)
    [ "$out" = "75" ]
}

@test "the fallback diagnostic goes to stderr, never to the status line" {
    # tmux's #() captures stdout only. A warning on stdout would be rendered
    # into the bar; a warning on stderr is what makes the failure diagnosable.
    export MOCK_OPT_useful_mem_warn="seventy"
    useful_config_reset
    out=$(useful_int_option "@useful-mem-warn" 75 2>/dev/null)
    [ "$out" = "75" ]
    err=$(useful_int_option "@useful-mem-warn" 75 2>&1 >/dev/null)
    [[ "$err" == *"@useful-mem-warn"* ]]
}

@test "values too large for a shell integer comparison are rejected" {
    # `[ 99999999999999999999 -ge 5 ]` fails with the same opaque error this
    # helper exists to prevent.
    export MOCK_OPT_useful_mem_warn="99999999999999999999"
    useful_config_reset
    out=$(useful_int_option "@useful-mem-warn" 75 2>/dev/null)
    [ "$out" = "75" ]
}

@test "valid numeric options pass through untouched" {
    export MOCK_OPT_useful_mem_warn=42
    useful_config_reset
    out=$(useful_int_option "@useful-mem-warn" 75 2>/dev/null)
    [ "$out" = "42" ]
}

@test "negative and empty values fall back" {
    for v in "-1" " " "1.5" "12abc"; do
        export MOCK_OPT_useful_mem_warn="$v"
        useful_config_reset
        out=$(useful_int_option "@useful-mem-warn" 75 2>/dev/null)
        [ "$out" = "75" ] || { echo "[$v] gave $out" >&2; return 1; }
    done
}

# ------------------------------------------------------- useful_icon_option

@test "an icon carries its own separating space" {
    icon=$(useful_icon_option "@useful-git-icon" "X")
    [ "$icon" = "X " ]
}

@test "an icon can actually be turned off" {
    # get_tmux_option treats "" as unset and hands back the default, so
    # clearing an icon needs an explicit word.
    for word in none off false no; do
        export MOCK_OPT_useful_git_icon="$word"
        useful_config_reset
        icon=$(useful_icon_option "@useful-git-icon" "X")
        [ -z "$icon" ] || { echo "[$word] left [$icon]" >&2; return 1; }
    done
}

# ----------------------------------------------------------- useful_timeout

@test "useful_timeout returns a fast command's output and status" {
    run useful_timeout 5 printf "quick"
    [ "$status" -eq 0 ]
    [ "$output" = "quick" ]
    run useful_timeout 5 sh -c "exit 7"
    [ "$status" -eq 7 ]
}

@test "useful_timeout bounds a command that would never return" {
    start=$(date +%s)
    run useful_timeout 1 sh -c "sleep 30"
    [ "$(( $(date +%s) - start ))" -lt 10 ]
}

@test "useful_timeout kills grandchildren, not just the direct child" {
    # The grandchild is what holds the command-substitution pipe open, so
    # signalling only the child left the caller blocked for the full runtime.
    start=$(date +%s)
    # `|| true`: a killed command exits non-zero, and bats runs the test body
    # under `set -e`, so the assignment alone would abort before the assertion.
    out=$(useful_timeout 1 sh -c "sleep 30 | cat") || true
    [ "$(( $(date +%s) - start ))" -lt 10 ]
    [ -z "$out" ]
}

@test "useful_timeout passes stdin through to the command" {
    # Bash redirects an async command's stdin from /dev/null unless there is an
    # explicit redirection — which silently ate spotify.sh's AppleScript
    # heredoc on stock macOS, the only platform that uses the fallback path.
    out=$(useful_timeout 5 cat <<'EOF'
piped-in
EOF
)
    [ "$out" = "piped-in" ]
}

@test "useful_timeout escalates to SIGKILL when the child ignores SIGTERM" {
    # SIGTERM is a request. A wrapper script, or anything with a
    # graceful-shutdown handler, can decline it — and then `wait` blocked
    # forever on exactly the hang the timeout exists to prevent, leaking the
    # child as an orphan on top.
    start=$(date +%s)
    run useful_timeout 1 bash -c 'trap "" TERM; sleep 60'
    [ "$(( $(date +%s) - start ))" -lt 15 ]
}

@test "a whole-run budget bounds the SUM of the guarded calls, not just each one" {
    # Ten independently-guarded sources at 3s each is 30s, however tight the
    # per-call limit looks.
    #
    # The bound is deliberately not the budget itself. Once it is spent each
    # remaining call still gets USEFUL_TIMEOUT_FLOOR plus its kill grace, so the
    # guarantee is "budget + about a second per pending call", not "budget".
    # Cancelling them instead would blank a healthy segment because an earlier
    # one hung. The threshold below is that guarantee, not slack.
    USEFUL_TIMEOUT_TOTAL=2
    start=$(date +%s)
    for _ in 1 2 3 4 5 6; do
        useful_timeout 5 sh -c "sleep 10" >/dev/null 2>&1 || true
    done
    [ "$(( $(date +%s) - start ))" -lt 12 ]
}

@test "the whole-run budget does not interfere with fast calls" {
    USEFUL_TIMEOUT_TOTAL=10
    run useful_timeout 5 printf "quick"
    [ "$output" = "quick" ]
}

# ------------------------------------------------------------ useful_escape

@test "useful_escape neutralises tmux format syntax" {
    run useful_escape '#[bg=red]x#{pane_id}'
    [ "$output" = '##[bg=red]x##{pane_id}' ]
}

@test "useful_escape leaves text without a hash alone" {
    run useful_escape 'feature/normal-branch'
    [ "$output" = 'feature/normal-branch' ]
}

@test "a timeout of 0 means no limit, on both code paths" {
    # coreutils timeout(1) reads 0 as unlimited. The watchdog used to read it
    # as `sleep 0; kill` and shoot the command immediately, so @useful-timeout 0
    # was an escape hatch that worked on Linux and broke on macOS.
    out=$(useful_timeout 0 sh -c "sleep 0.4; echo alive" 2>/dev/null) || true
    [ "$out" = "alive" ] || { echo "gave [$out]" >&2; return 1; }
    # ...and it disables the whole-run ceiling with it, rather than swapping one
    # bound for another.
    USEFUL_TIMEOUT_TOTAL=1
    out=$(useful_timeout 0 sh -c "sleep 2; echo alive" 2>/dev/null) || true
    [ "$out" = "alive" ]
}

@test "a torn cache entry cannot bleed colour into the segments after it" {
    # A tee killed mid-write leaves a colour run open, and tmux carries that
    # colour through every later segment for the whole TTL.
    cache_file="$TMUX_USEFUL_CACHE_DIR/torn"
    printf "%s" " #[fg=#bf616a]!cpu5" >"$cache_file"
    run cache_check "$cache_file" 60
    [ "$status" -eq 0 ]
    [[ "$output" == *"#[fg=default]" ]]
}

@test "a well-formed cache entry is returned byte-for-byte" {
    cache_file="$TMUX_USEFUL_CACHE_DIR/ok"
    printf "%s" " #[fg=#bf616a]!cpu 90%#[fg=default]" >"$cache_file"
    run cache_check "$cache_file" 60
    [ "$output" = " #[fg=#bf616a]!cpu 90%#[fg=default]" ]
}

@test "control bytes in a corrupted cache entry never reach the terminal" {
    cache_file="$TMUX_USEFUL_CACHE_DIR/corrupt"
    printf 'a\rb\x1b[2Jc' >"$cache_file"
    out=$(cache_check "$cache_file" 60)
    case "$out" in
        *$'\r'*|*$'\x1b'*) echo "control byte survived: [$out]" >&2; return 1 ;;
    esac
}

@test "an absurdly long cache entry is recomputed, not pasted into the bar" {
    cache_file="$TMUX_USEFUL_CACHE_DIR/huge"
    printf 'x%.0s' $(seq 1 10000) >"$cache_file"
    run cache_check "$cache_file" 60
    [ "$status" -ne 0 ]
}

@test "an empty cache entry still counts as a hit" {
    # Segments write an empty file to mean "nothing to show"; that must not be
    # mistaken for a miss and recomputed every refresh.
    cache_file="$TMUX_USEFUL_CACHE_DIR/empty"
    : >"$cache_file"
    run cache_check "$cache_file" 60
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

# ------------------------------------------------- cache dir creation + trust

@test "@useful-cache-dir is created, not merely echoed" {
    # It used to be echoed straight back: the mkdir only ran on the derived
    # path. A user pointing the option at a directory that did not exist yet
    # lost EVERY segment's cache silently, because tee's error goes to a stderr
    # tmux discards.
    target="$TMUX_USEFUL_CACHE_DIR/made/up/deep"
    export MOCK_OPT_useful_cache_dir="$target"
    useful_config_reset
    run useful_cache_dir
    [ "$output" = "$target" ]
    [ -d "$target" ]
}

@test "TMUX_USEFUL_CACHE_DIR is created too" {
    target="$TMUX_USEFUL_CACHE_DIR/env/override"
    TMUX_USEFUL_CACHE_DIR="$target" useful_config_reset
    run env TMUX_USEFUL_CACHE_DIR="$target" bash -c \
        "source '$SCRIPTS_DIR/helpers.sh'; useful_cache_dir"
    [ "$output" = "$target" ]
    [ -d "$target" ]
}

@test "a cache dir we do not own is refused, not trusted" {
    # mkdir succeeds on an existing directory whoever owns it, so creating it
    # is not proof it is ours. A directory another user can write is a
    # directory that can write the status line.
    export MOCK_OPT_useful_cache_dir="/"     # exists, and is not owned by us
    useful_config_reset
    run useful_cache_dir
    [ "$output" != "/" ]
    [ -n "$output" ]
    [ -d "$output" ]
}

@test "a cache dir we create is private to us" {
    target="$TMUX_USEFUL_CACHE_DIR/private"
    export MOCK_OPT_useful_cache_dir="$target"
    useful_config_reset
    useful_cache_dir >/dev/null
    perms=$(ls -ld "$target" | cut -c1-10)
    [ "$perms" = "drwx------" ]
}

# ------------------------------------------------------------------ useful_hash

@test "useful_hash is stable and distinguishes its inputs" {
    a=$(useful_hash "/home/me/project-one")
    b=$(useful_hash "/home/me/project-two")
    [ -n "$a" ]
    [ "$a" != "$b" ]
    [ "$a" = "$(useful_hash "/home/me/project-one")" ]
}

@test "useful_hash still distinguishes inputs with no shasum on PATH" {
    # musl distros ship sha1sum, not shasum; a Debian without perl ships
    # neither. An empty key is not a degraded key, it is a COLLIDING one --
    # every repo shared one "git-" cache entry and showed the wrong branch.
    stub="$TMUX_USEFUL_CACHE_DIR/nohash"
    mkdir -p "$stub"
    for c in shasum sha1sum cksum; do
        printf '#!/bin/sh\nexit 127\n' >"$stub/$c"
        chmod +x "$stub/$c"
    done
    a=$(PATH="$stub:$PATH" useful_hash "/home/me/project-one")
    b=$(PATH="$stub:$PATH" useful_hash "/home/me/project-two")
    [ -n "$a" ]
    [ "$a" != "$b" ]
}

# -------------------------------------------------- cache entries are markup

@test "a cache entry carrying markup we never write is refused" {
    # Sanitising the bytes is not enough: the danger is the markup. A planted
    # entry used to reach the bar verbatim, background block and all.
    cache_file="$TMUX_USEFUL_CACHE_DIR/planted"
    printf '%s' ' #[bg=red]#[fg=#ff0000]PWNED#[fg=default]' >"$cache_file"
    run cache_check "$cache_file" 60
    [ "$status" -ne 0 ]
}

@test "a cache entry carrying a format expansion is refused" {
    cache_file="$TMUX_USEFUL_CACHE_DIR/planted2"
    printf '%s' ' #{pane_current_path}' >"$cache_file"
    run cache_check "$cache_file" 60
    [ "$status" -ne 0 ]
}

@test "our own colour markup still round-trips through the cache" {
    cache_file="$TMUX_USEFUL_CACHE_DIR/ours"
    printf '%s' ' #[fg=#bf616a]!mem 95%#[fg=default]' >"$cache_file"
    run cache_check "$cache_file" 60
    [ "$status" -eq 0 ]
    [ "$output" = ' #[fg=#bf616a]!mem 95%#[fg=default]' ]
}

@test "escaped untrusted text in a cache entry still round-trips" {
    # useful_escape doubles '#', so "##[fg=" is legitimate cache content.
    cache_file="$TMUX_USEFUL_CACHE_DIR/escaped"
    printf '%s' ' #[fg=#7b8696]branch##[fg=red]#[fg=default]' >"$cache_file"
    run cache_check "$cache_file" 60
    [ "$status" -eq 0 ]
}

# ---------------------------------------------------------------- ansi colours

@test "a malformed hex colour renders no escape and no error" {
    run bash -c "source '$SCRIPTS_DIR/helpers.sh'; useful_render ansi '#[fg=#gggggg]hi#[fg=default]' 2>&1"
    [ "$status" -eq 0 ]
    case "$output" in *"value too great for base"*) return 1 ;; esac
    case "$output" in *hi*) ;; *) return 1 ;; esac
}
