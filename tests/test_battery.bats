#!/usr/bin/env bats
# Tests for scripts/battery.sh

load 'test_helpers'

setup() {
    setup_test_env
}

teardown() {
    teardown_test_env
}

run_battery() {
    run "$SCRIPTS_DIR/battery.sh"
}

@test "100% on AC → charging glyph 󰂄, green" {
    export MOCK_BATT_AC=1
    export MOCK_BATT_PCT=100
    run_battery
    [ "$status" -eq 0 ]
    [[ "$output" == *"󰂄"* ]]
    [[ "$output" == *"100%"* ]]
    [[ "$output" == *"#[fg=#a3be8c]"* ]]
}

@test "100% on battery → glyph 󰂂, green" {
    export MOCK_BATT_AC=0
    export MOCK_BATT_PCT=100
    run_battery
    [[ "$output" == *"󰂂"* ]]
    [[ "$output" == *"#[fg=#a3be8c]"* ]]
}

@test "30% on battery (< default warn 40) → yellow" {
    export MOCK_BATT_AC=0
    export MOCK_BATT_PCT=30
    run_battery
    [[ "$output" == *"#[fg=#ebcb8b]"* ]]
    [[ "$output" == *"30%"* ]]
}

@test "10% on battery (< default crit 20) → red" {
    export MOCK_BATT_AC=0
    export MOCK_BATT_PCT=10
    run_battery
    [[ "$output" == *"#[fg=#bf616a]"* ]]
}

@test "10% on AC → green (charging overrides low warning)" {
    export MOCK_BATT_AC=1
    export MOCK_BATT_PCT=10
    run_battery
    [[ "$output" == *"󰂄"* ]]
    [[ "$output" == *"#[fg=#a3be8c]"* ]]
}

@test "pmset returns no output → empty" {
    export MOCK_PMSET_EMPTY=1
    run_battery
    [ "$output" = "" ]
}

@test "custom batt-warn threshold respected" {
    export MOCK_BATT_AC=0
    export MOCK_BATT_PCT=60
    export MOCK_OPT_useful_batt_warn=80   # 60 < 80 → warn
    run_battery
    [[ "$output" == *"#[fg=#ebcb8b]"* ]]
}

@test "glyph progression by percent" {
    export MOCK_BATT_AC=0
    for pct_glyph in "92:󰂂" "80:󰂀" "65:󰁾" "50:󰁼" "35:󰁺" "20:󰁻" "5:󰂃"; do
        pct="${pct_glyph%%:*}"
        glyph="${pct_glyph##*:}"
        export MOCK_BATT_PCT="$pct"
        rm -f "$TMUX_USEFUL_CACHE_DIR"/tmux-useful-battery-cache
        run_battery
        [[ "$output" == *"$glyph"* ]] || {
            echo "expected glyph '$glyph' for $pct%, got: $output" >&2
            return 1
        }
    done
}
