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

@test "a leading U+FE0F does not promote a glyph that is not there" {
    # Regression: the promotion state started at "previous glyph was narrow",
    # so a variation selector at position 0 invented an extra cell.
    width_is "$(printf '\xef\xb8\x8f')ab" 2
    # ...while promotion after a real narrow glyph still works.
    width_is "☁️" 2
    # ...and never applies after a glyph that is already wide.
    width_is "字$(printf '\xef\xb8\x8f')" 2
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

@test "a budget too small for the ellipsis yields nothing, not an overflow" {
    useful_truncate "abcdef" 0
    [ "$USEFUL_TRUNC" = "" ]
    useful_truncate "abcdef" 1
    [ "$USEFUL_TRUNC" = "…" ]
    # A 2-cell ellipsis against a 1-cell budget must also come back empty.
    useful_truncate "abcdef" 1 "字"
    [ "$USEFUL_TRUNC" = "" ]
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

# --------------------------------------------------------- malformed UTF-8
#
# The decoder used to trust any byte >= 0xC0 as a multi-byte lead. One invalid
# byte then swallowed up to three following ASCII characters, so the measured
# width came out short and the "budget" it produced overflowed the terminal.

@test "an invalid lead byte counts as one cell, not as a multi-byte sequence" {
    # "a<BAD> b" is four printed columns in any terminal: a, one replacement
    # glyph, a space, b. Each of these bytes is illegal as a UTF-8 lead.
    for bad in c0 c1 f5 fe ff; do
        s=$(printf "a\\x${bad} b")
        useful_display_width "$s"
        [ "$USEFUL_WIDTH" -eq 4 ] || { echo "0x$bad measured $USEFUL_WIDTH, want 4" >&2; return 1; }
    done
}

@test "a lead byte followed by a non-continuation byte does not eat it" {
    # 0xC2 IS a legal lead, but a space is not a legal continuation. The pair
    # is one bad byte plus a real space, not one two-byte character.
    s=$(printf "a\xc2 b")
    useful_display_width "$s"
    [ "$USEFUL_WIDTH" -eq 4 ]
}

@test "a truncated sequence at end of string invents no glyph" {
    # Missing continuation bytes used to decode as zeroes, which manufactured
    # a wide CJK codepoint out of nothing.
    s=$(printf "abc\xe4\xb8")
    useful_display_width "$s"
    [ "$USEFUL_WIDTH" -eq 5 ]
}

@test "a window over text containing an invalid byte still fits its budget" {
    s=$(printf "Art\xffistNameHereeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeeee")
    useful_window "$s" 0 29
    # Every byte here is single-cell (ASCII, plus one replacement glyph), so
    # bytes out must not exceed the cell budget.
    [ "$(printf "%s" "$USEFUL_WINDOW" | wc -c | tr -d ' ')" -le 29 ]
}

# ------------------------------------------------- zero-width mark clamping
#
# Combining marks measure zero cells, so a cell budget alone is not a bound on
# anything: 500 stacked acutes measure ONE cell and sail through any test of
# the form "does it fit". The clamp is what turns the budget into a real bound.

@test "an unbounded run of combining marks is clamped, not passed through" {
    marks=$(printf "\xCC\x81%.0s" $(seq 1 500))
    useful_truncate "x${marks}" 5
    [ "${#USEFUL_TRUNC}" -le 6 ]
}

@test "the clamp survives the driver, on a field nobody else controls" {
    # A Spotify track title has no filesystem length limit behind it, unlike a
    # git branch name — it is the widest-open input the plugin reads.
    marks=$(printf "\xCC\x81%.0s" $(seq 1 400))
    export MOCK_SPOTIFY_RUNNING=1 TMUX_USEFUL_NO_WATCHDOG=1
    export MOCK_SPOTIFY_TRACK="Artist${marks}|Song"
    run "$SCRIPTS_DIR/spotify.sh"
    [ "$status" -eq 0 ]
    [ "${#output}" -lt 100 ]
}

@test "legitimate stacking is still preserved" {
    # Up to USEFUL_MAX_MARKS marks ride along untouched; real scripts never
    # need more, and this is the line between "clamped" and "mangled".
    for n in 1 2 3 4; do
        marks=$(printf "\xCC\x81%.0s" $(seq 1 "$n"))
        useful_truncate "e${marks}" 10
        [ "$USEFUL_TRUNC" = "e${marks}" ] || { echo "$n marks mangled" >&2; return 1; }
    done
}

@test "clamping does not disturb ordinary text" {
    useful_truncate "feature/some-branch" 8
    [ "$USEFUL_TRUNC" = "feature…" ]
    useful_truncate "hello" 10
    [ "$USEFUL_TRUNC" = "hello" ]
    useful_truncate "日本語テスト" 8
    [ "$USEFUL_TRUNC" = "日本語…" ]
}

# ------------------------------------------- overlong / surrogate / out-of-range
#
# Rejecting bad LEAD bytes was only half of it. The first continuation byte has
# a narrower legal range for four leads (RFC 3629), and accepting the full
# 0x80-0xBF there admitted overlong forms, UTF-16 surrogates, and codepoints
# past U+10FFFF — each decoded as one narrow cell where a compliant terminal
# draws one replacement glyph PER BYTE.

@test "overlong, surrogate and out-of-range sequences count one cell per byte" {
    #                lead+continuations           expected width of "a<seq>b"
    for probe in 'e0 80 80:5' 'ed a0 80:5' 'f0 80 80 80:6' 'f4 90 80 80:6'; do
        seq="${probe%%:*}"; want="${probe#*:}"
        esc=""; for b in $seq; do esc="${esc}\\x${b}"; done
        s=$(printf "a${esc}b")
        useful_display_width "$s"
        [ "$USEFUL_WIDTH" -eq "$want" ] \
            || { echo "[$seq] measured $USEFUL_WIDTH, want $want" >&2; return 1; }
    done
}

@test "an overlong-encoded string cannot overflow its truncation budget" {
    # 24 x "\xe0\x80\x80" measured 24 cells and rendered 72 columns.
    s=""
    for _ in $(seq 1 24); do s="${s}$(printf '\xe0\x80\x80')"; done
    useful_truncate "$s" 24
    useful_display_width "$USEFUL_TRUNC"
    [ "$USEFUL_WIDTH" -le 24 ]
}

@test "legal sequences at the edge of those ranges still decode" {
    # The narrowing must not eat the smallest legal 3- and 4-byte forms, the
    # last codepoint before the surrogate block, or the last legal codepoint.
    # U+10FFFF lands in plane-16 private use, which useful_cp_width calls narrow
    # on purpose (see its closing comment) — so 1 cell here is the intended
    # answer, not an artefact of the narrowing.
    for probe in 'e0 a0 80:1' 'ed 9f bf:1' 'f0 90 80 80:1' 'f4 8f bf bf:1'; do
        seq="${probe%%:*}"; want="${probe#*:}"
        esc=""; for b in $seq; do esc="${esc}\\x${b}"; done
        s=$(printf "$esc")
        useful_display_width "$s"
        [ "$USEFUL_WIDTH" -eq "$want" ] \
            || { echo "[$seq] measured $USEFUL_WIDTH, want $want" >&2; return 1; }
    done
}

# ------------------------------------------------------------ budget ceiling

@test "a cell budget is capped at USEFUL_MAX_CELLS" {
    # bash's ${var//pat/rep} is quadratic in match count, and useful_escape
    # doubles every '#'. An uncapped max-len turned a hash-dense response into
    # minutes of CPU, so a budget wider than any terminal is refused.
    s=$(printf 'x%.0s' $(seq 1 4000))
    useful_truncate "$s" 20000
    useful_display_width "$USEFUL_TRUNC"
    [ "$USEFUL_WIDTH" -le "$USEFUL_MAX_CELLS" ]
}

@test "truncation cost tracks the budget, not the input length" {
    # useful_truncate used to measure the whole string just to learn it did not
    # fit. Decoding 40k characters to answer a 24-cell question is work with no
    # answer in it; a generous ceiling here still catches a return to O(length).
    s=$(printf '#%.0s' $(seq 1 40000))
    start=$(date +%s)
    useful_truncate "$s" 24
    [ "$(( $(date +%s) - start ))" -lt 10 ]
    useful_display_width "$USEFUL_TRUNC"
    [ "$USEFUL_WIDTH" -le 24 ]
}

# ------------------------------------ the clamp is not a truncation
#
# USEFUL_WINDOW_CUT_TAIL decides whether an ellipsis is owed, so it has to mean
# "renderable content was left behind", and nothing else. Letting the mark clamp
# set it too put a "…" on strings that fitted, and at an exact fit stole a real
# character to make room for the marker.

@test "excess marks do not conjure an ellipsis onto content that fits" {
    s="hi"
    for _ in $(seq 1 6); do s="${s}$(printf '\xcc\x81')"; done
    s="${s}bye"
    useful_truncate "$s" 20
    case "$USEFUL_TRUNC" in *…*) echo "spurious ellipsis: $USEFUL_TRUNC" >&2; return 1 ;; esac
    [[ "$USEFUL_TRUNC" == *bye ]]
}

@test "content that fits exactly keeps its last character" {
    s="hi"
    for _ in $(seq 1 6); do s="${s}$(printf '\xcc\x81')"; done
    s="${s}bye"                       # 5 visible cells once clamped
    useful_truncate "$s" 5
    [[ "$USEFUL_TRUNC" == *bye ]]
    case "$USEFUL_TRUNC" in *…*) echo "ellipsis on an exact fit: $USEFUL_TRUNC" >&2; return 1 ;; esac
}

@test "a genuine overflow still gets its ellipsis" {
    s="hi"
    for _ in $(seq 1 6); do s="${s}$(printf '\xcc\x81')"; done
    s="${s}bye"
    useful_truncate "$s" 4
    [[ "$USEFUL_TRUNC" == *… ]]
    useful_display_width "$USEFUL_TRUNC"
    [ "$USEFUL_WIDTH" -le 4 ]
}

@test "an inflated budget does not mark a short string as truncated" {
    # The USEFUL_MAX_CELLS cap lowers the budget; that is not itself a cut.
    useful_truncate "abc" 20000
    [ "$USEFUL_TRUNC" = "abc" ]
}

@test "the clamp reports itself separately from a truncation" {
    s="e"
    for _ in $(seq 1 9); do s="${s}$(printf '\xcc\x81')"; done
    useful_window "$s" 0 10
    [ "$USEFUL_WINDOW_MARKS_CLAMPED" -eq 1 ]
    [ "$USEFUL_WINDOW_CUT_TAIL" -eq 0 ]

    useful_window "abcdefghij" 0 3
    [ "$USEFUL_WINDOW_MARKS_CLAMPED" -eq 0 ]
    [ "$USEFUL_WINDOW_CUT_TAIL" -eq 1 ]
}

@test "a run of only zero-width marks cannot make the scan unbounded" {
    # `taken` never advances for zero-width glyphs, so the budget alone could
    # not stop the loop: a 20k-mark title walked the whole input on stock
    # defaults, in pure bash, where no timeout can reach it.
    # Built with printf's repeat-count form, not a 20,000-iteration append loop:
    # that loop forks per iteration and re-copies a growing string, costing ~61s
    # of fixture construction before the call under test even runs. A timing
    # test whose own scaffolding dominates the clock is how a slow harness gets
    # mistaken for slow code.
    s="a$(printf '\xcc\x81%.0s' $(seq 1 20000))bbb"
    start=$(date +%s)
    useful_truncate "$s" 24
    [ "$(( $(date +%s) - start ))" -lt 5 ]
}

@test "giving up the scan is reported separately from a budget overflow" {
    # Bounding the scan trades fidelity for a bound: content sitting after an
    # oversized mark run is past the byte cut and is lost. That is deliberate —
    # bash 3.2 cannot skip a mark run cheaply, and no real text carries
    # thousands of stacked marks — but the two claims "we stopped looking" and
    # "the tail did not fit" must not be told apart only by guesswork.
    marks=$(printf '\xcc\x81%.0s' $(seq 1 20000))
    useful_window "a${marks}bbb" 0 24
    [ "$USEFUL_WINDOW_SCAN_LIMITED" -eq 1 ]
    [ "$USEFUL_WINDOW_CUT_TAIL" -eq 1 ]

    # An ordinary overflow is a budget overflow, and says only that.
    useful_window "abcdefghij" 0 3
    [ "$USEFUL_WINDOW_SCAN_LIMITED" -eq 0 ]
    [ "$USEFUL_WINDOW_CUT_TAIL" -eq 1 ]

    # And a string that fits claims neither.
    useful_window "abc" 0 10
    [ "$USEFUL_WINDOW_SCAN_LIMITED" -eq 0 ]
    [ "$USEFUL_WINDOW_CUT_TAIL" -eq 0 ]

    # A long but ordinary string gets pre-cut too. That is not "giving up":
    # the budget was filled from what remained, so nothing reachable was lost
    # and only CUT_TAIL is owed.
    useful_window "$(printf 'x%.0s' $(seq 1 40000))" 0 24
    [ "$USEFUL_WINDOW_SCAN_LIMITED" -eq 0 ]
    [ "$USEFUL_WINDOW_CUT_TAIL" -eq 1 ]
}
