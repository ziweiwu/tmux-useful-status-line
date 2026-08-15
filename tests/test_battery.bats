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

@test "100% on AC by default → visible with charging glyph + percent" {
    export MOCK_BATT_AC=1
    export MOCK_BATT_PCT=100
    run_battery
    [ "$status" -eq 0 ]
    [[ "$output" == *"󰂄"* ]]
    [[ "$output" == *"100%"* ]]
    [[ "$output" == *"#[fg=#a3be8c]"* ]]
}

@test "show-when=discharging-or-low hides 100% on AC" {
    export MOCK_BATT_AC=1
    export MOCK_BATT_PCT=100
    export MOCK_OPT_useful_batt_show_when=discharging-or-low
    run_battery
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}

@test "show-when=discharging-or-low shows 94% on AC (below full=95)" {
    export MOCK_BATT_AC=1
    export MOCK_BATT_PCT=94
    export MOCK_OPT_useful_batt_show_when=discharging-or-low
    run_battery
    [[ "$output" == *"94%"* ]]
}

@test "show-when=low-only hides healthy battery" {
    export MOCK_BATT_AC=0
    export MOCK_BATT_PCT=80
    export MOCK_OPT_useful_batt_show_when=low-only
    run_battery
    [ "$output" = "" ]
}

@test "show-when=low-only shows when below warn" {
    export MOCK_BATT_AC=0
    export MOCK_BATT_PCT=30
    export MOCK_OPT_useful_batt_show_when=low-only
    run_battery
    [[ "$output" == *"30%"* ]]
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

@test "10% on battery (< default crit 20) → red with '!' prefix" {
    export MOCK_BATT_AC=0
    export MOCK_BATT_PCT=10
    run_battery
    [[ "$output" == *"#[fg=#bf616a]"* ]]
    [[ "$output" == *"!"* ]]
}

@test "healthy, warn and crit are all distinguishable without colour" {
    # Battery renders in every state under the default show-when, so healthy vs
    # warn used to differ by hue alone — the glyph tiers are a charge gauge
    # (90/60/30/15), not a severity scale, so a warn 39% and a healthy 45% draw
    # the SAME mid glyph. The prefixes carry the severity: "" / "~" / "!".
    export MOCK_BATT_AC=0
    export MOCK_BATT_PCT=80
    run_battery
    [[ "$output" != *"~"* ]]
    [[ "$output" != *"!"* ]]

    export MOCK_BATT_PCT=30
    rm -f "$TMUX_USEFUL_CACHE_DIR/battery"
    run_battery
    [[ "$output" == *"~"* ]]
    [[ "$output" != *"!"* ]]

    export MOCK_BATT_PCT=5
    rm -f "$TMUX_USEFUL_CACHE_DIR/battery"
    run_battery
    [[ "$output" == *"!"* ]]
    [[ "$output" != *"~"* ]]
}

@test "crit is '!' here exactly as it is in the system segment beside it" {
    # A status line is read as one line. Letting crit vary per segment made
    # `!mem 95%` sit beside `!!batt 15%` and claim the battery was worse when
    # both were critical — false to the one audience that has only the prefix.
    export MOCK_BATT_AC=0 MOCK_BATT_PCT=5
    for mode in always discharging-or-low low-only; do
        export MOCK_OPT_useful_batt_show_when="$mode"
        rm -f "$TMUX_USEFUL_CACHE_DIR/battery"
        run_battery
        [[ "$output" == *"!"* ]] || { echo "$mode lost the crit marker" >&2; return 1; }
        [[ "$output" != *"!!"* ]] || { echo "$mode doubled the crit marker" >&2; return 1; }
    done
}

@test "low-only mode gives warn no prefix — presence is already the cue there" {
    export MOCK_BATT_AC=0
    export MOCK_BATT_PCT=30
    export MOCK_OPT_useful_batt_show_when=low-only
    run_battery
    [ -n "$output" ]
    [[ "$output" != *"~"* ]]
}

@test "ASCII icons toggle replaces nerd-font glyphs" {
    export MOCK_BATT_AC=0
    export MOCK_BATT_PCT=80
    export MOCK_OPT_useful_batt_icons_ascii=on
    run_battery
    [[ "$output" == *"[### ]"* ]]
    [[ "$output" != *"󰂀"* ]]
}

@test "custom icon override takes effect" {
    export MOCK_BATT_AC=1
    export MOCK_BATT_PCT=80
    export MOCK_OPT_useful_batt_icon_charging="⚡"
    run_battery
    [[ "$output" == *"⚡"* ]]
}

@test "segment disabled → empty even when discharging low" {
    export MOCK_BATT_AC=0
    export MOCK_BATT_PCT=10
    export MOCK_OPT_useful_battery_enabled=off
    run_battery
    [ "$output" = "" ]
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

@test "glyph progression by percent (5-tier ladder)" {
    export MOCK_BATT_AC=0
    # Tiers: ≥90 full, ≥60 high, ≥30 mid, ≥15 low, <15 empty.
    for pct_glyph in "92:󰂂" "80:󰂀" "65:󰂀" "50:󰁾" "35:󰁾" "20:󰁺" "5:󰂃"; do
        pct="${pct_glyph%%:*}"
        glyph="${pct_glyph##*:}"
        export MOCK_BATT_PCT="$pct"
        rm -f "$TMUX_USEFUL_CACHE_DIR"/battery
        run_battery
        [[ "$output" == *"$glyph"* ]] || {
            echo "expected glyph '$glyph' for $pct%, got: $output" >&2
            return 1
        }
    done
}

@test "@useful-batt-crit-prefix can suppress the '!' marker" {
    # Parity with system.sh's per-metric crit prefixes: a user who wants
    # colour-only crit signalling everywhere could not get it for battery.
    export MOCK_BATT_AC=0 MOCK_BATT_PCT=5
    run_battery
    [[ "$output" == *"!"* ]]
    export MOCK_OPT_useful_batt_crit_prefix="none"
    rm -f "$TMUX_USEFUL_CACHE_DIR/battery"
    run_battery
    [[ "$output" != *"!"* ]]
}

@test "@useful-batt-crit-prefix can be changed rather than removed" {
    export MOCK_BATT_AC=0 MOCK_BATT_PCT=5
    export MOCK_OPT_useful_batt_crit_prefix="LOW "
    run_battery
    [[ "$output" == *"LOW "* ]]
}

@test "a non-numeric threshold falls back instead of blanking the segment" {
    export MOCK_BATT_AC=0 MOCK_BATT_PCT=25
    export MOCK_OPT_useful_batt_warn="forty"
    run_battery
    [ "$status" -eq 0 ]
    [[ "$output" == *"25%"* ]]
}

@test "an unreadable battery percentage is not rendered as a number" {
    export MOCK_PMSET_EMPTY=1
    run_battery
    [ "$status" -eq 0 ]
    [ "$output" = "" ]
}
