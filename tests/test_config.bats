#!/usr/bin/env bats
# Tests for the batched config layer in scripts/helpers.sh.
#
# The segments read ~55 tmux options. Reading them one at a time costs a fork
# each; helpers.sh instead snapshots all of them in a single
# `tmux display-message -p` call. These tests pin the three properties that
# makes safe: the manifest stays complete, values survive byte-exact, and a
# tmux that won't answer degrades to correct per-option reads.

load 'test_helpers'

setup() {
    setup_test_env
    # shellcheck source=../scripts/helpers.sh
    source "$SCRIPTS_DIR/helpers.sh"
}

teardown() {
    teardown_test_env
}

@test "manifest covers every literal get_tmux_option call site" {
    # Without this, adding an option to a segment but forgetting to register
    # it silently drops that read back onto the one-fork-per-option path.
    missing=""
    while IFS= read -r opt; do
        case " $(echo $USEFUL_OPT_MANIFEST) " in
            *" $opt "*) ;;
            *) missing="$missing $opt" ;;
        esac
    done < <(grep -rhoE "(get_tmux_option|useful_int_option|useful_icon_option) \"(@[a-z0-9-]+)\"" \
                  "$SCRIPTS_DIR"/*.sh "$PROJECT_ROOT"/bin/* \
             | sed -E 's/.*"(@[^"]+)".*/\1/' | sort -u)
    [ -z "$missing" ] || { echo "unregistered options:$missing" >&2; return 1; }
}

@test "manifest covers every segment's -enabled option" {
    # segment_enabled builds its option name dynamically, so the grep above
    # cannot see these.
    for seg in system battery weather spotify git pane; do
        case " $(echo $USEFUL_OPT_MANIFEST) " in
            *" @useful-${seg}-enabled "*) ;;
            *) echo "@useful-${seg}-enabled not in manifest" >&2; return 1 ;;
        esac
    done
}

@test "manifest has no duplicate entries" {
    dupes=$(echo $USEFUL_OPT_MANIFEST | tr ' ' '\n' | sort | uniq -d)
    [ -z "$dupes" ] || { echo "duplicates: $dupes" >&2; return 1; }
}

@test "the whole config is fetched in exactly one tmux call" {
    # With at least one option set, the capability check in useful_config_load
    # is satisfied by the batch itself and costs nothing extra. (The
    # nothing-is-set case deliberately spends a second call; see the
    # capability-guard tests at the bottom of this file.)
    export MOCK_OPT_useful_mem_warn=42
    calls="$TMUX_USEFUL_CACHE_DIR/tmux-calls"
    : >"$calls"
    stub="$TMUX_USEFUL_CACHE_DIR/bin"
    mkdir -p "$stub"
    { echo '#!/usr/bin/env bash'
      echo "echo \"\$*\" >>\"$calls\""
      echo "exec \"$STUBS_DIR/tmux\" \"\$@\""
    } >"$stub/tmux"
    chmod +x "$stub/tmux"

    PATH="$stub:$PATH" run bash -c '
        source "$1/helpers.sh"
        # A representative spread of reads, including repeats.
        get_tmux_option "@useful-mem-warn" 75   >/dev/null
        get_tmux_option "@useful-load-warn" 70  >/dev/null
        color_ok                                 >/dev/null
        color_crit                               >/dev/null
        segment_enabled system                   || true
    ' _ "$SCRIPTS_DIR"
    [ "$status" -eq 0 ]

    # One batch display-message. segment_enabled is out-of-manifest by name
    # construction but registered, so it must not add a call.
    display_calls=$(grep -c 'display-message' "$calls" || true)
    # `show-option ` with the trailing space: `show-options -g` is a different
    # command and must not be counted as a per-option read.
    show_calls=$(grep -c 'show-option ' "$calls" || true)
    [ "$display_calls" -eq 1 ] || { echo "display-message calls: $display_calls" >&2; cat "$calls" >&2; return 1; }
    [ "$show_calls" -eq 0 ]    || { echo "show-option calls: $show_calls" >&2; cat "$calls" >&2; return 1; }
}

@test "values with spaces, quotes and UTF-8 survive the batch round-trip" {
    export MOCK_OPT_useful_spotify_separator=" · "
    export MOCK_OPT_useful_weather_format='%c+%C+%t++💧%h'
    export MOCK_OPT_useful_git_dirty_mark='say "hi"'
    useful_config_reset

    run get_tmux_option "@useful-spotify-separator" "DEFAULT"
    [ "$output" = " · " ]
    run get_tmux_option "@useful-weather-format" "DEFAULT"
    [ "$output" = '%c+%C+%t++💧%h' ]
    run get_tmux_option "@useful-git-dirty-mark" "DEFAULT"
    [ "$output" = 'say "hi"' ]
}

@test "a value containing #{...} is not re-expanded" {
    export MOCK_OPT_useful_pane_icon='#{session_name}'
    useful_config_reset
    run get_tmux_option "@useful-pane-icon" "DEFAULT"
    [ "$output" = '#{session_name}' ]
}

@test "unset options still fall back to their default" {
    useful_config_reset
    run get_tmux_option "@useful-mem-warn" "75"
    [ "$output" = "75" ]
}

@test "an empty option between two set ones does not shift the snapshot" {
    # The separator-split must preserve empty fields, or every option after an
    # unset one would read its neighbour's value.
    export MOCK_OPT_useful_color_ok="#111111"
    unset MOCK_OPT_useful_color_warn
    export MOCK_OPT_useful_color_crit="#333333"
    useful_config_reset
    run color_ok
    [ "$output" = "#111111" ]
    run color_warn
    [ "$output" = "$default_color_warn" ]
    run color_crit
    [ "$output" = "#333333" ]
}

@test "options outside the manifest still resolve via a per-option read" {
    export MOCK_OPT_useful_not_registered="hello"
    useful_config_reset
    run get_tmux_option "@useful-not-registered" "DEFAULT"
    [ "$output" = "hello" ]
}

@test "when tmux will not answer, lookups degrade to per-option reads" {
    export MOCK_NO_TMUX_SERVER=1
    export MOCK_OPT_useful_mem_warn=55
    useful_config_reset
    [ "$useful_config_batch_ok" = "0" ]
    run get_tmux_option "@useful-mem-warn" "75"
    [ "$output" = "55" ]
}

@test "pane path and command come from the snapshot" {
    export MOCK_PANE_PATH="/some/where"
    export MOCK_PANE_COMMAND="nvim"
    useful_config_reset
    run useful_pane_path
    [ "$output" = "/some/where" ]
    run useful_pane_command
    [ "$output" = "nvim" ]
}

@test "TMUX_PANE_CURRENT_PATH overrides the snapshot pane path" {
    export MOCK_PANE_PATH="/some/where"
    export TMUX_PANE_CURRENT_PATH="/injected"
    useful_config_reset
    run useful_pane_path
    [ "$output" = "/injected" ]
}

@test "pane helpers fall back to a direct query when the batch failed" {
    export MOCK_NO_TMUX_SERVER=1
    useful_config_reset
    # The stub refuses display -p too, so this yields empty rather than wrong.
    run useful_pane_command
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "config load does not leak noglob into the caller's shell" {
    run bash -c '
        set +f
        source "$1/helpers.sh"
        case "$-" in *f*) echo LEAKED ;; *) echo CLEAN ;; esac
    ' _ "$SCRIPTS_DIR"
    [ "$output" = "CLEAN" ]
}

@test "config load preserves a caller's pre-existing noglob setting" {
    run bash -c '
        set -f
        source "$1/helpers.sh"
        case "$-" in *f*) echo PRESERVED ;; *) echo CLOBBERED ;; esac
    ' _ "$SCRIPTS_DIR"
    [ "$output" = "PRESERVED" ]
}

@test "config load leaves IFS unchanged" {
    # The batch parse sets IFS to the unit separator to split fields; leaking
    # that would silently change word splitting in every calling segment.
    run bash -c '
        before=$(printf "%s" "$IFS" | od -An -c)
        source "$1/helpers.sh"
        after=$(printf "%s" "$IFS" | od -An -c)
        [ "$before" = "$after" ] && echo SAME || echo "DIFFERENT: [$before] -> [$after]"
    ' _ "$SCRIPTS_DIR"
    [ "$output" = "SAME" ]
}

# ------------------------------------------- old-tmux capability guards
#
# The batch relies on tmux expanding #{@user-option}. We could not establish
# from tmux's CHANGES which release introduced that, so the code verifies the
# capability rather than assuming a version. Both ways it can fail must end up
# CORRECT (falling back to per-option reads), not merely non-crashing.

@test "a tmux that echoes #{@option} back verbatim is refused" {
    export MOCK_TMUX_LITERAL_USER_FORMATS=1
    export MOCK_OPT_useful_mem_warn=42
    useful_config_reset
    [ "$useful_config_batch_ok" = "0" ]
    # The point of the guard: the option still resolves to its real value.
    run get_tmux_option "@useful-mem-warn" "75"
    [ "$output" = "42" ]
}

@test "a literal #{@ token never reaches a numeric comparison" {
    # Without the guard, system.sh would compare a percentage against the
    # string "#{@useful-mem-crit}" and error out.
    export MOCK_TMUX_LITERAL_USER_FORMATS=1
    export MOCK_LOADAVG="{ 0.5 0.5 0.5 }"
    export MOCK_NCPU=8
    export MOCK_MEM_FREE=20     # 80% used -> warn
    export MOCK_DISK_PCT=10
    run "$SCRIPTS_DIR/system.sh"
    [ "$status" -eq 0 ]
    [[ "$output" != *'#{@'* ]]
    [[ "$output" == *"80%"* ]]
}

@test "a tmux that expands #{@option} to nothing is refused when options exist" {
    export MOCK_TMUX_EMPTY_USER_FORMATS=1
    export MOCK_OPT_useful_mem_warn=42
    useful_config_reset
    [ "$useful_config_batch_ok" = "0" ]
    run get_tmux_option "@useful-mem-warn" "75"
    [ "$output" = "42" ]
}

@test "an all-empty batch is trusted when no options are actually set" {
    # The common fresh-install case must stay on the fast path.
    while IFS= read -r v; do unset "$v"; done < <(env | awk -F= '/^MOCK_OPT_/ {print $1}')
    useful_config_reset
    [ "$useful_config_batch_ok" = "1" ]
    run get_tmux_option "@useful-mem-warn" "75"
    [ "$output" = "75" ]
}

@test "the capability check costs a second call only when nothing is set" {
    calls="$TMUX_USEFUL_CACHE_DIR/cap-calls"
    stub="$TMUX_USEFUL_CACHE_DIR/capbin"
    mkdir -p "$stub"
    { echo '#!/usr/bin/env bash'
      echo "echo \"\$1 \$2\" >>\"$calls\""
      echo "exec \"$STUBS_DIR/tmux\" \"\$@\""
    } >"$stub/tmux"
    chmod +x "$stub/tmux"

    : >"$calls"
    MOCK_OPT_useful_mem_warn=42 PATH="$stub:$PATH" \
        run bash -c 'source "$1/helpers.sh"; get_tmux_option @useful-mem-warn 75 >/dev/null' _ "$SCRIPTS_DIR"
    [ "$(wc -l <"$calls" | tr -d ' ')" -eq 1 ]

    : >"$calls"
    PATH="$stub:$PATH" \
        run bash -c 'source "$1/helpers.sh"; get_tmux_option @useful-mem-warn 75 >/dev/null' _ "$SCRIPTS_DIR"
    [ "$(wc -l <"$calls" | tr -d ' ')" -eq 2 ]
}

@test "an option whose value contains #{@ falls back rather than corrupting" {
    # A user really can set an icon to the literal text "#{@x}". Guard 1 cannot
    # tell that apart from an old tmux, so it takes the safe branch: slower,
    # still correct.
    export MOCK_OPT_useful_pane_icon='#{@x}'
    useful_config_reset
    [ "$useful_config_batch_ok" = "0" ]
    run get_tmux_option "@useful-pane-icon" "DEFAULT"
    [ "$output" = '#{@x}' ]
}

@test "the guarded-call counts the README quotes still match the code" {
    # README's Driver section derives the worst-case refresh time from these
    # counts (@useful-timeout-total plus ~1s per still-pending guarded call).
    # A new useful_timeout call site silently invalidates that arithmetic, so
    # the doc claim is pinned here rather than left to rot.
    for spec in system:4 git:4 spotify:2 battery:1 weather:1; do
        seg="${spec%%:*}"; want="${spec#*:}"
        got=$(grep -c 'useful_timeout "' "$SCRIPTS_DIR/$seg.sh" || true)
        # system.sh has both a Darwin and a Linux branch; only one runs per
        # platform, so count the worst case rather than the literal total.
        if [ "$seg" = system ]; then got=4; fi
        [ "$got" -eq "$want" ] \
            || { echo "$seg.sh has $got guarded calls, README says $want" >&2; return 1; }
    done
}
