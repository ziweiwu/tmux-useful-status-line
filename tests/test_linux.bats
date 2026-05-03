#!/usr/bin/env bats
# Cross-platform tests: exercise Linux code paths even on macOS CI by
# overriding TMUX_USEFUL_OS_OVERRIDE=Linux + injecting fake /proc and
# /sys/class/power_supply directories.

load 'test_helpers'

setup() {
    setup_test_env
    export TMUX_USEFUL_OS_OVERRIDE=Linux
    PROC_DIR="$TMUX_USEFUL_CACHE_DIR/proc"
    POWER_DIR="$TMUX_USEFUL_CACHE_DIR/power"
    mkdir -p "$PROC_DIR" "$POWER_DIR"
    export TMUX_USEFUL_PROC="$PROC_DIR"
    export TMUX_USEFUL_SYS_POWER="$POWER_DIR"
    # Sane defaults for the proc filesystem.
    echo "0.50 0.40 0.30 1/100 12345" > "$PROC_DIR/loadavg"
    : > "$PROC_DIR/cpuinfo"
}

teardown() {
    teardown_test_env
}

# ---------------- system.sh on Linux ----------------

@test "linux system: load read from /proc/loadavg" {
    echo "8.00 7.00 6.00 1/100 12345" > "$PROC_DIR/loadavg"
    export MOCK_NCPU=8
    export MOCK_MEM_USED_PCT=20
    export MOCK_DISK_PCT=10
    run "$SCRIPTS_DIR/system.sh"
    [ "$status" -eq 0 ]
    # 8/8 cores = 100% → crit ("!cpu 100%")
    [[ "$output" == *"100%"* ]]
}

@test "linux system: memory percent computed from free's 'available' column" {
    export MOCK_NCPU=8
    export MOCK_MEM_USED_PCT=80     # 80% used → warn
    export MOCK_DISK_PCT=10
    run "$SCRIPTS_DIR/system.sh"
    [[ "$output" == *"80%"* ]]
    [[ "$output" == *"#[fg=#ebcb8b]"* ]]
}

@test "linux system: disk threshold logic still works" {
    export MOCK_NCPU=8
    export MOCK_MEM_USED_PCT=20
    export MOCK_DISK_PCT=98
    run "$SCRIPTS_DIR/system.sh"
    [[ "$output" == *"98%"* ]]
    [[ "$output" == *"#[fg=#bf616a]"* ]]
}

# ---------------- battery.sh on Linux ----------------

@test "linux battery: discharging at 60% → high-tier glyph in OK color" {
    mkdir -p "$POWER_DIR/BAT0"
    echo 60 > "$POWER_DIR/BAT0/capacity"
    echo "Discharging" > "$POWER_DIR/BAT0/status"
    run "$SCRIPTS_DIR/battery.sh"
    [ "$status" -eq 0 ]
    [[ "$output" == *"60%"* ]]
    [[ "$output" == *"#[fg=#a3be8c]"* ]]
}

@test "linux battery: charging glyph used when status=Charging" {
    mkdir -p "$POWER_DIR/BAT0"
    echo 50 > "$POWER_DIR/BAT0/capacity"
    echo "Charging" > "$POWER_DIR/BAT0/status"
    run "$SCRIPTS_DIR/battery.sh"
    [[ "$output" == *"󰂄"* ]]
}

@test "linux battery: low + discharging triggers crit '!' prefix" {
    mkdir -p "$POWER_DIR/BAT0"
    echo 10 > "$POWER_DIR/BAT0/capacity"
    echo "Discharging" > "$POWER_DIR/BAT0/status"
    run "$SCRIPTS_DIR/battery.sh"
    [[ "$output" == *"!"* ]]
    [[ "$output" == *"#[fg=#bf616a]"* ]]
}

@test "linux battery: BAT1 used when BAT0 missing" {
    mkdir -p "$POWER_DIR/BAT1"
    echo 75 > "$POWER_DIR/BAT1/capacity"
    echo "Discharging" > "$POWER_DIR/BAT1/status"
    run "$SCRIPTS_DIR/battery.sh"
    [[ "$output" == *"75%"* ]]
}

@test "linux battery: no battery devices → empty" {
    run "$SCRIPTS_DIR/battery.sh"
    [ "$output" = "" ]
}
