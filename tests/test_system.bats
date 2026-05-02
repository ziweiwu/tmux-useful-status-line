#!/usr/bin/env bats
# Tests for scripts/system.sh

load 'test_helpers'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

run_system() {
    run "$SCRIPTS_DIR/system.sh"
}

@test "all metrics healthy → empty output" {
    export MOCK_LOADAVG="{ 0.50 0.40 0.30 }"
    export MOCK_NCPU=8
    export MOCK_MEM_FREE=80   # 20% used → below default warn 75
    export MOCK_DISK_PCT=10
    run_system
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "load above warn (70% of cores) → yellow" {
    export MOCK_LOADAVG="{ 6.50 6.0 6.0 }"   # 6.5/8 = 81% → warn
    export MOCK_NCPU=8
    export MOCK_MEM_FREE=80
    export MOCK_DISK_PCT=10
    run_system
    [ "$status" -eq 0 ]
    [[ "$output" == *"#[fg=#ebcb8b]"* ]]
    [[ "$output" == *"6.50"* ]]
}

@test "load above crit (≥100% of cores) → red" {
    export MOCK_LOADAVG="{ 12.0 12.0 12.0 }"
    export MOCK_NCPU=8
    export MOCK_MEM_FREE=80
    export MOCK_DISK_PCT=10
    run_system
    [[ "$output" == *"#[fg=#bf616a]"* ]]
}

@test "memory above warn → yellow MEM" {
    export MOCK_LOADAVG="{ 0.5 0.5 0.5 }"
    export MOCK_NCPU=8
    export MOCK_MEM_FREE=20    # 80% used → ≥ warn 75
    export MOCK_DISK_PCT=10
    run_system
    [[ "$output" == *"#[fg=#ebcb8b]"*"80%"* ]]
}

@test "memory above crit → red MEM" {
    export MOCK_LOADAVG="{ 0.5 0.5 0.5 }"
    export MOCK_NCPU=8
    export MOCK_MEM_FREE=5     # 95% used
    export MOCK_DISK_PCT=10
    run_system
    [[ "$output" == *"#[fg=#bf616a]"*"95%"* ]]
}

@test "disk above warn → yellow DISK" {
    export MOCK_LOADAVG="{ 0.5 0.5 0.5 }"
    export MOCK_NCPU=8
    export MOCK_MEM_FREE=80
    export MOCK_DISK_PCT=85
    run_system
    [[ "$output" == *"#[fg=#ebcb8b]"*"85%"* ]]
}

@test "disk above crit → red DISK" {
    export MOCK_LOADAVG="{ 0.5 0.5 0.5 }"
    export MOCK_NCPU=8
    export MOCK_MEM_FREE=80
    export MOCK_DISK_PCT=98
    run_system
    [[ "$output" == *"#[fg=#bf616a]"*"98%"* ]]
}

@test "all three above warn → all three concatenated" {
    export MOCK_LOADAVG="{ 7.0 7.0 7.0 }"
    export MOCK_NCPU=8
    export MOCK_MEM_FREE=20    # 80% used
    export MOCK_DISK_PCT=85
    run_system
    [[ "$output" == *"7.0"* ]]
    [[ "$output" == *"80%"* ]]
    [[ "$output" == *"85%"* ]]
    [[ "$output" == *"#[fg=default]"* ]]
}

@test "custom thresholds via @useful-mem-warn override defaults" {
    export MOCK_LOADAVG="{ 0.5 0.5 0.5 }"
    export MOCK_NCPU=8
    export MOCK_MEM_FREE=50    # 50% used
    export MOCK_DISK_PCT=10
    export MOCK_OPT_useful_mem_warn=30   # 50 ≥ 30 → warn
    run_system
    [[ "$output" == *"50%"* ]]
}

@test "cache hit returns cached output without recomputation" {
    export MOCK_LOADAVG="{ 7.0 7.0 7.0 }"
    export MOCK_NCPU=8
    export MOCK_MEM_FREE=80
    export MOCK_DISK_PCT=10
    run_system
    first="$output"
    # Now change inputs but cache should still return first result.
    export MOCK_LOADAVG="{ 0.1 0.1 0.1 }"
    run_system
    [ "$output" = "$first" ]
}
