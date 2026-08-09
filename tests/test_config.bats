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
    done < <(grep -rhoE 'get_tmux_option "(@[a-z0-9-]+)"' \
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
    show_calls=$(grep -c 'show-option' "$calls" || true)
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
