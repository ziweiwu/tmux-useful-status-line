#!/usr/bin/env bats
# Tests for the display-width layer in scripts/helpers.sh.
#
# Status-line layout is budgeted in terminal CELLS. ${#s} counts characters,
# which for CJK and emoji is half the truth. These pin the classifier and the
# two consumers of it (truncation and the Spotify slide window).

load 'test_helpers'

setup() {
    setup_test_env
    # shellcheck source=../scripts/helpers.sh
    source "$SCRIPTS_DIR/helpers.sh"
}

teardown() {
    teardown_test_env
}

width_is() {
    useful_display_width "$1"
    [ "$USEFUL_WIDTH" -eq "$2" ] || {
        echo "width(\"$1\") = $USEFUL_WIDTH, expected $2" >&2; return 1; }
}

@test "ASCII is one cell per character" {
    width_is "hello" 5
    width_is "" 0
    width_is "a b" 3
}

@test "CJK ideographs and kana are two cells" {
    width_is "字" 2
    width_is "坂本龍一" 8
    width_is "ひらがな" 8
    width_is "한글" 4
}

@test "fullwidth forms are two cells" {
    width_is "（）" 4
    width_is "Ａ" 2
}

@test "Latin-1, Greek and Cyrillic stay one cell" {
    width_is "café" 4
    width_is "αβγ" 3
    width_is "привет" 6
}

@test "emoji are two cells" {
    width_is "💧" 2
    width_is "💨" 2
}

@test "U+FE0F promotes the preceding narrow glyph to two cells" {
    # The weather segment emits exactly this: U+2601 alone is narrow, but the
    # variation selector requests emoji presentation.
    width_is "☁" 1
    width_is "☁️" 2
}

@test "combining marks occupy no cells" {
    # "e" + U+0301 combining acute
    width_is "$(printf 'e\xcc\x81')" 1
}

@test "block-element glyphs stay one cell" {
    # The CPU bar is built from these; calling them wide would halve the bar.
    width_is "█" 1
    width_is "░" 1
    width_is "██████████" 10
}

@test "private-use glyphs stay one cell" {
    # Nerd Font icons live in the PUA and render single-width. Built with
    # printf rather than pasted, so the bytes are unambiguous in this file.
    width_is "$(printf '\xee\x82\xa0')" 1   # U+E0A0 branch
    width_is "$(printf '\xf3\xb0\x82\x84')" 1   # U+F0084 battery charging
}

@test "arrows and dingbats stay one cell" {
    width_is "→" 1
    width_is "·" 1
}

@test "mixed strings sum correctly" {
    width_is "feature/用户认证系统重构与优化方案第二版" 40
    width_is "☁️ 23°C 💧89%" 13
}

# ------------------------------------------------------------------ truncation

@test "truncate is a no-op when the string already fits" {
    useful_truncate "short" 20
    [ "$USEFUL_TRUNC" = "short" ]
}

@test "truncate cuts ASCII to the budget including the ellipsis" {
    useful_truncate "Lorem ipsum dolor" 10
    [ "$USEFUL_TRUNC" = "Lorem ips…" ] || { echo "got [$USEFUL_TRUNC]" >&2; return 1; }
    useful_display_width "$USEFUL_TRUNC"
    [ "$USEFUL_WIDTH" -eq 10 ]
}

@test "truncated output never exceeds the budget, for any of these inputs" {
    # The property that actually matters: whatever we emit fits the bar.
    for s in "plain ascii string here" \
             "feature/用户认证系统重构与优化方案第二版" \
             "坂本龍一 · 戦場のメリークリスマス" \
             "☁️ 23°C 💧89% 💨→17km/h" \
             "한글과 English 혼합" \
             "→→→→→→→→→→→→→→→→→→→→"; do
        for budget in 4 8 12 16 24 30; do
            useful_truncate "$s" "$budget"
            useful_display_width "$USEFUL_TRUNC"
            [ "$USEFUL_WIDTH" -le "$budget" ] || {
                echo "budget=$budget got width=$USEFUL_WIDTH for [$USEFUL_TRUNC]" >&2
                return 1; }
        done
    done
}

@test "truncate never splits a multi-byte character" {
    # An odd budget against 2-cell glyphs is where a naive slice would tear one.
    useful_truncate "坂本龍一坂本龍一" 7
    # Round-trip through printf: a torn character would not survive as-is.
    [ "$(printf '%s' "$USEFUL_TRUNC")" = "$USEFUL_TRUNC" ]
    useful_display_width "$USEFUL_TRUNC"
    [ "$USEFUL_WIDTH" -le 7 ]
}

@test "truncate keeps the ellipsis intact" {
    # Regression: on bash 3.2 an unbraced "$VAR…" swallows the ellipsis's
    # leading 0xE2 byte into the variable name, emitting two stray bytes.
    useful_truncate "Lorem ipsum dolor" 10
    case "$USEFUL_TRUNC" in
        *…) ;;
        *) echo "ellipsis mangled: [$USEFUL_TRUNC]" >&2; return 1 ;;
    esac
}

# ---------------------------------------------------------------- windowing

@test "window extracts a run at a cell offset" {
    useful_window "abcdefghij" 3 4
    [ "$USEFUL_WINDOW" = "defg" ]
    [ "$USEFUL_WINDOW_CUT_HEAD" -eq 1 ]
    [ "$USEFUL_WINDOW_CUT_TAIL" -eq 1 ]
}

@test "window reports no cuts when it spans the whole string" {
    useful_window "abc" 0 10
    [ "$USEFUL_WINDOW" = "abc" ]
    [ "$USEFUL_WINDOW_CUT_HEAD" -eq 0 ]
    [ "$USEFUL_WINDOW_CUT_TAIL" -eq 0 ]
}

@test "window respects a cell budget across wide glyphs" {
    # 5 cells cannot hold three 2-cell glyphs, and must not half-draw one.
    useful_window "坂本龍一" 0 5
    useful_display_width "$USEFUL_WINDOW"
    [ "$USEFUL_WIDTH" -le 5 ]
    [ "$USEFUL_WINDOW" = "坂本" ]
}

@test "window with a zero or negative budget yields nothing" {
    useful_window "abc" 0 0
    [ "$USEFUL_WINDOW" = "" ]
}

# ------------------------------------------------------- segment integration

@test "git truncates a CJK branch name to the cell budget" {
    REPO="$TMUX_USEFUL_CACHE_DIR/repo"
    mkdir -p "$REPO" && cd "$REPO"
    git init -q . 2>/dev/null
    git -c user.email=t@t -c user.name=t commit -q --allow-empty -m init 2>/dev/null
    git checkout -q -b "feature/用户认证系统重构与优化方案第二版" 2>/dev/null
    export TMUX_PANE_CURRENT_PATH="$REPO"
    export MOCK_OPT_useful_git_max_branch_len=24
    run "$SCRIPTS_DIR/git.sh"
    [ "$status" -eq 0 ]
    text=$(printf '%s' "$output" | sed -E 's/#\[[^]]*\]//g')
    text="${text# }"
    source "$SCRIPTS_DIR/helpers.sh"
    useful_display_width "$text"
    # icon + space + branch; the branch itself must be inside 24 cells.
    [ "$USEFUL_WIDTH" -le 26 ] || { echo "rendered $USEFUL_WIDTH cells: [$text]" >&2; return 1; }
}

@test "pane truncates a wide command name to the cell budget" {
    export MOCK_PANE_COMMAND="編集器プログラム実行中"
    export MOCK_OPT_useful_pane_max_len=10
    run "$SCRIPTS_DIR/pane.sh"
    text=$(printf '%s' "$output" | sed -E 's/#\[[^]]*\]//g')
    text="${text# }"; text="${text#* }"
    source "$SCRIPTS_DIR/helpers.sh"
    useful_display_width "$text"
    [ "$USEFUL_WIDTH" -le 10 ] || { echo "got $USEFUL_WIDTH cells: [$text]" >&2; return 1; }
}
