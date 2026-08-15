#!/usr/bin/env bats
# Tests for bin/useful-status — the single-process driver.

load 'test_helpers'

setup() {
    setup_test_env
    DRIVER="$PROJECT_ROOT/bin/useful-status"
    # A healthy, fully deterministic machine.
    export MOCK_LOADAVG="{ 0.50 0.40 0.30 }"
    export MOCK_NCPU=8
    export MOCK_MEM_FREE=80
    export MOCK_DISK_PCT=10
    export MOCK_PANE_COMMAND=nvim
}

teardown() {
    teardown_test_env
}

@test "--list prints every segment name, one per line" {
    run "$DRIVER" --list
    [ "$status" -eq 0 ]
    [ "${#lines[@]}" -eq 6 ]
    [[ "$output" == *"system"* ]]
    [[ "$output" == *"battery"* ]]
    [[ "$output" == *"git"* ]]
}

@test "driver output matches the concatenated individual scripts" {
    # This is the contract that lets the driver replace six #() calls.
    export MOCK_MEM_FREE=20   # 80% used → warn, so there is something to render
    export MOCK_DISK_PCT=85

    a=$("$SCRIPTS_DIR/system.sh")
    rm -f "$TMUX_USEFUL_CACHE_DIR"/system
    b=$("$SCRIPTS_DIR/pane.sh")
    rm -f "$TMUX_USEFUL_CACHE_DIR"/system
    combined="$b$a"

    run "$DRIVER" --render=tmux --segments=pane,system
    [ "$output" = "$combined" ]
}

@test "--segments controls both membership and order" {
    run "$DRIVER" --render=plain --segments=pane
    pane_only="$output"
    [ -n "$pane_only" ]

    export MOCK_MEM_FREE=20
    run "$DRIVER" --render=plain --segments=pane,system
    ab="$output"
    run "$DRIVER" --render=plain --segments=system,pane
    ba="$output"
    [ "$ab" != "$ba" ]
}

@test "a segment produces the same text regardless of its position" {
    # The segment bodies use globals; the driver isolates them per subshell.
    # If that isolation broke, order would change the rendered values.
    export MOCK_MEM_FREE=20
    run "$DRIVER" --render=plain --segments=system
    alone="$output"
    run "$DRIVER" --render=plain --segments=pane,system
    with_pane="$output"
    [[ "$with_pane" == *"$alone"* ]]
}

@test "disabled segments are omitted" {
    export MOCK_OPT_useful_pane_enabled=off
    run "$DRIVER" --render=plain --segments=pane
    [ "$output" = "" ]
}

@test "healthy system stays silent through the driver too" {
    run "$DRIVER" --render=plain --segments=system
    [ "$output" = "" ]
}

@test "--render=tmux emits tmux markup" {
    run "$DRIVER" --render=tmux --segments=pane
    [[ "$output" == *"#[fg="* ]]
}

@test "--render=ansi emits SGR escapes and no tmux markup" {
    run "$DRIVER" --render=ansi --segments=pane
    [[ "$output" == *"$(printf '\033')["* ]]
    [[ "$output" != *"#[fg="* ]]
}

@test "--render=plain emits neither markup nor escapes" {
    run "$DRIVER" --render=plain --segments=pane
    [[ "$output" != *"#[fg="* ]]
    [[ "$output" != *"$(printf '\033')["* ]]
    [[ "$output" == *"nvim"* ]]
}

@test "--render=json reports text, class and per-segment severity" {
    export MOCK_MEM_FREE=5    # 95% used → critical
    run "$DRIVER" --render=json --segments=system,pane
    [ "$status" -eq 0 ]
    [[ "$output" == *'"class":"critical"'* ]]
    [[ "$output" == *'"name":"system"'* ]]
    [[ "$output" == *'"severity":"critical"'* ]]
    [[ "$output" == *'"name":"pane"'* ]]
    # No tmux markup should survive into JSON text fields.
    [[ "$output" != *"#[fg="* ]]
}

@test "--render=json emits a valid object even when every segment is silent" {
    run "$DRIVER" --render=json --segments=system
    [ "$status" -eq 0 ]
    [ "$output" = '{"text":"","class":"none","segments":[]}' ]
}

@test "--separator is inserted between non-empty segments only" {
    export MOCK_MEM_FREE=20
    run "$DRIVER" --render=plain --separator=' | ' --segments=pane,system
    [[ "$output" == *" | "* ]]
    # With only one non-empty segment there is nothing to separate.
    run "$DRIVER" --render=plain --separator=' | ' --segments=pane
    [[ "$output" != *" | "* ]]
}

@test "unknown segment name exits 2 with a message" {
    run "$DRIVER" --segments=nope
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown segment"* ]]
}

@test "unknown render mode exits 2 with a message" {
    run "$DRIVER" --render=hologram
    [ "$status" -eq 2 ]
    [[ "$output" == *"unknown render mode"* ]]
}

@test "unknown flag exits 2 and prints usage" {
    run "$DRIVER" --wat
    [ "$status" -eq 2 ]
    [[ "$output" == *"usage:"* ]]
}

@test "--help exits 0" {
    run "$DRIVER" --help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage:"* ]]
}

@test "@useful-render option is honoured when no flag is given" {
    export MOCK_OPT_useful_render=plain
    run "$DRIVER" --segments=pane
    [[ "$output" != *"#[fg="* ]]
    [[ "$output" == *"nvim"* ]]
}

@test "@useful-segments option is honoured when no flag is given" {
    export MOCK_OPT_useful_segments="pane"
    export MOCK_MEM_FREE=5    # would be loudly critical if system ran
    run "$DRIVER" --render=plain
    [[ "$output" == *"nvim"* ]]
    [[ "$output" != *"mem"* ]]
}

@test "an explicit flag overrides the tmux option" {
    export MOCK_OPT_useful_render=plain
    run "$DRIVER" --render=tmux --segments=pane
    [[ "$output" == *"#[fg="* ]]
}

@test "segments run against one shared config snapshot" {
    # One option set means useful_config_load's capability check is answered by
    # the batch itself, so the whole refresh is a single tmux round-trip. With
    # nothing set it deliberately spends one extra call; see test_config.bats.
    export MOCK_OPT_useful_mem_warn=42
    calls="$TMUX_USEFUL_CACHE_DIR/calls"
    : >"$calls"
    stub="$TMUX_USEFUL_CACHE_DIR/bin"
    mkdir -p "$stub"
    { echo '#!/usr/bin/env bash'
      echo "echo \"\$1 \$2\" >>\"$calls\""
      echo "exec \"$STUBS_DIR/tmux\" \"\$@\""
    } >"$stub/tmux"
    chmod +x "$stub/tmux"

    PATH="$stub:$PATH" run "$DRIVER" --render=plain
    [ "$status" -eq 0 ]
    n=$(wc -l <"$calls" | tr -d ' ')
    [ "$n" -eq 1 ] || { echo "expected 1 tmux call, got $n:" >&2; cat "$calls" >&2; return 1; }
}

# ------------------------------------------------------------ CLI citizenship

@test "--version prints a version and exits 0" {
    run "$DRIVER" --version
    [ "$status" -eq 0 ]
    [[ "$output" == "useful-status "* ]]
    run "$DRIVER" -V
    [ "$status" -eq 0 ]
}

@test "outside tmux with a non-tty stdout, output is plain" {
    # bats captures stdout through a pipe, which is exactly the piped case.
    unset TMUX
    run "$DRIVER" --segments=pane
    [[ "$output" != *"#[fg="* ]]
    [[ "$output" != *"$(printf '\033')["* ]]
    [[ "$output" == *"nvim"* ]]
}

@test "inside tmux, tmux markup wins over the non-tty check" {
    # tmux runs #() with stdout as a pipe; a naive isatty test would break it.
    export TMUX=/tmp/tmux-fake
    run "$DRIVER" --segments=pane
    [[ "$output" == *"#[fg="* ]]
}

@test "NO_COLOR makes the non-tmux default plain" {
    unset TMUX
    export NO_COLOR=1
    run "$DRIVER" --segments=pane
    [[ "$output" != *"$(printf '\033')["* ]]
    [[ "$output" == *"nvim"* ]]
}

@test "an explicit --render still wins over NO_COLOR" {
    unset TMUX
    export NO_COLOR=1
    run "$DRIVER" --render=ansi --segments=pane
    [[ "$output" == *"$(printf '\033')["* ]]
}

@test "@useful-render still wins over the non-tty default" {
    unset TMUX
    export MOCK_OPT_useful_render=ansi
    run "$DRIVER" --segments=pane
    [[ "$output" == *"$(printf '\033')["* ]]
}

@test "a wedged segment does not silence the healthy segments after it" {
    # The driver runs segments in a fixed order off one shared clock. A budget
    # that CANCELS later calls once the clock is spent makes a healthy battery
    # vanish because git hung — the bar goes blank for a reason that has nothing
    # to do with the segment that disappeared, which is the exact opposite of
    # "silent when healthy, loud when it isn't".
    hangdir="$(mktemp -d)"
    printf '#!/usr/bin/env bash\ntrap "" TERM\nsleep 300\n' >"$hangdir/git"
    chmod +x "$hangdir/git"
    export PATH="$hangdir:$PATH"
    export MOCK_OPT_useful_timeout=1
    export MOCK_OPT_useful_timeout_total=2
    export MOCK_BATT_AC=0 MOCK_BATT_PCT=50

    run "$PROJECT_ROOT/bin/useful-status" --render=plain --segments=git,battery
    [ "$status" -eq 0 ]
    [[ "$output" == *"50%"* ]]
    rm -rf "$hangdir"
}
