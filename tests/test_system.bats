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
    [[ "$output" == *"81%"* ]]   # 6.5/8 = 81%
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

@test "crit warnings get a leading '!' for color-blind users" {
    export MOCK_LOADAVG="{ 12.0 12.0 12.0 }"
    export MOCK_NCPU=8
    export MOCK_MEM_FREE=5     # 95% used → crit
    export MOCK_DISK_PCT=98    # crit
    run_system
    # Each crit warning prefixed with "!" — three exclamation marks.
    [ "$(printf "%s" "$output" | tr -cd '!' | wc -c)" -eq 3 ]
}

@test "warn warnings do NOT get the '!' prefix" {
    export MOCK_LOADAVG="{ 0.5 0.5 0.5 }"
    export MOCK_NCPU=8
    export MOCK_MEM_FREE=20    # 80% → warn (not crit)
    export MOCK_DISK_PCT=85    # warn
    run_system
    [[ "$output" != *"!"* ]]
}

@test "show-when=mem-and-disk-always renders healthy mem and disk in dim" {
    export MOCK_LOADAVG="{ 0.1 0.1 0.1 }"   # healthy
    export MOCK_NCPU=8
    export MOCK_MEM_FREE=80                  # 20% used → healthy
    export MOCK_DISK_PCT=10                  # healthy
    export MOCK_OPT_useful_system_show_when=mem-and-disk-always
    run_system
    [[ "$output" == *"#[fg=#7b8696]"* ]]
    [[ "$output" == *"20%"* ]]
    [[ "$output" == *"10%"* ]]
}

@test "show-when=mem-and-disk-always omits healthy load" {
    export MOCK_LOADAVG="{ 0.1 0.1 0.1 }"
    export MOCK_NCPU=8
    export MOCK_MEM_FREE=80
    export MOCK_DISK_PCT=10
    export MOCK_OPT_useful_system_show_when=mem-and-disk-always
    run_system
    [[ "$output" != *"0.1"* ]]
}

@test "show-when=all-always renders healthy load too" {
    export MOCK_LOADAVG="{ 0.1 0.1 0.1 }"
    export MOCK_NCPU=8
    export MOCK_MEM_FREE=80
    export MOCK_DISK_PCT=10
    export MOCK_OPT_useful_system_show_when=all-always
    run_system
    # 0.1/8 = 1% — the always-mode shows it as "cpu 1%".
    [[ "$output" == *"cpu"* ]]
    [[ "$output" == *"1%"* ]]
}

@test "warn band overrides healthy-color even when always-mode is on" {
    export MOCK_LOADAVG="{ 0.1 0.1 0.1 }"
    export MOCK_NCPU=8
    export MOCK_MEM_FREE=20                  # 80% → warn
    export MOCK_DISK_PCT=10
    export MOCK_OPT_useful_system_show_when=mem-and-disk-always
    run_system
    [[ "$output" == *"#[fg=#ebcb8b]"* ]]     # warn yellow on mem
    [[ "$output" == *"#[fg=#7b8696]"* ]]     # dim on healthy disk
}

@test "segment disabled → empty even with critical metrics" {
    export MOCK_OPT_useful_system_enabled=off
    export MOCK_LOADAVG="{ 12.0 12.0 12.0 }"
    export MOCK_NCPU=8
    export MOCK_MEM_FREE=5
    export MOCK_DISK_PCT=98
    run_system
    [ "$output" = "" ]
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
