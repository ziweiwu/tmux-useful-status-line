#!/usr/bin/env bats
# Tests for the render translation layer in scripts/helpers.sh.
#
# Segments always emit tmux markup. These pin the translation of that markup
# into the syntaxes non-tmux hosts need.

load 'test_helpers'

setup() {
    setup_test_env
    # shellcheck source=../scripts/helpers.sh
    source "$SCRIPTS_DIR/helpers.sh"
    ESC=$(printf '\033')
}

teardown() {
    teardown_test_env
}

@test "tmux mode passes markup through untouched" {
    run useful_render tmux ' #[fg=#bf616a]!cpu 90%#[fg=default]'
    [ "$output" = ' #[fg=#bf616a]!cpu 90%#[fg=default]' ]
}

@test "plain mode strips every format directive" {
    run useful_render plain ' #[fg=#bf616a]!cpu 90%#[fg=default]'
    [ "$output" = ' !cpu 90%' ]
}

@test "ansi mode converts hex to a 24-bit SGR sequence" {
    run useful_render ansi '#[fg=#bf616a]X'
    [ "$output" = "${ESC}[38;2;191;97;106mX" ]
}

@test "ansi mode converts fg=default to the SGR default-foreground reset" {
    run useful_render ansi 'X#[fg=default]'
    [ "$output" = "X${ESC}[39m" ]
}

@test "ansi mode handles hex components that are not valid octal" {
    # $((16#08)) style arithmetic would break if the value were treated as
    # octal — 08 and 09 are the canaries.
    run useful_render ansi '#[fg=#080909]X'
    [ "$output" = "${ESC}[38;2;8;9;9mX" ]
}

@test "ansi mode handles uppercase hex" {
    run useful_render ansi '#[fg=#BF616A]X'
    [ "$output" = "${ESC}[38;2;191;97;106mX" ]
}

@test "ansi mode maps tmux colourN to a 256-colour SGR sequence" {
    run useful_render ansi '#[fg=colour123]X'
    [ "$output" = "${ESC}[38;5;123mX" ]
    run useful_render ansi '#[fg=color9]Y'
    [ "$output" = "${ESC}[38;5;9mY" ]
}

@test "ansi mode maps the basic colour names" {
    run useful_render ansi '#[fg=red]X'
    [ "$output" = "${ESC}[31mX" ]
    run useful_render ansi '#[fg=cyan]X'
    [ "$output" = "${ESC}[36mX" ]
}

@test "an unrecognised attribute is dropped rather than emitted raw" {
    run useful_render ansi '#[bg=red,bold]X'
    [ "$output" = "X" ]
}

@test "multiple directives in one string all translate" {
    run useful_render plain ' #[fg=#a]a #[fg=#b]b#[fg=default]'
    [ "$output" = ' a b' ]
}

@test "text with no directives is returned unchanged in every mode" {
    for mode in tmux ansi plain; do
        run useful_render "$mode" 'plain text'
        [ "$output" = 'plain text' ] || { echo "mode $mode gave: $output" >&2; return 1; }
    done
}

@test "empty input yields empty output in every mode" {
    for mode in tmux ansi plain; do
        run useful_render "$mode" ''
        [ "$output" = '' ] || { echo "mode $mode gave: $output" >&2; return 1; }
    done
}

@test "UTF-8 content survives translation" {
    run useful_render plain '#[fg=#bf616a]☁️ 23°C 💧89%#[fg=default]'
    [ "$output" = '☁️ 23°C 💧89%' ]
}

@test "severity is inferred from the palette tone used" {
    run useful_severity " #[fg=$(color_crit)]!mem 95%#[fg=default]"
    [ "$output" = "critical" ]
    run useful_severity " #[fg=$(color_warn)]mem 80%#[fg=default]"
    [ "$output" = "warning" ]
    run useful_severity " #[fg=$(color_dim)]mem 20%#[fg=default]"
    [ "$output" = "normal" ]
    run useful_severity "no colour here"
    [ "$output" = "none" ]
}

@test "severity tracks a theme override rather than hard-coded hexes" {
    export MOCK_OPT_useful_color_crit="#123456"
    useful_config_reset
    run useful_severity " #[fg=#123456]boom#[fg=default]"
    [ "$output" = "critical" ]
}

@test "json escaping handles quotes and backslashes" {
    run useful_json_escape 'say "hi" \ ok'
    [ "$output" = 'say \"hi\" \\ ok' ]
}
