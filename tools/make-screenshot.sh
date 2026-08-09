#!/usr/bin/env bash
# Regenerate assets/status-line.svg from REAL segment output.
#
# The bar content is produced by running bin/useful-status against the test
# stubs, so the picture cannot drift from what the plugin actually emits — if a
# segment changes, re-run this and the image follows. Only the chrome (session
# name, branch, clock, window rect) is drawn here.
#
# Rows are laid out the way tmux lays out a status line: a left chunk, computed
# padding, and a right chunk, all inside one left-aligned <text>. Right-aligning
# with text-anchor="end" is not reliable across SVG renderers — content ran off
# the edge — and padding is faithful to how the real bar works anyway.
#
# Icons use the Nerd-Font-free variants: GitHub renders this with whatever font
# the reader has, and Nerd Font codepoints would be tofu for most people.
#
# Usage: tools/make-screenshot.sh [output.svg]
set -eu

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
OUT="${1:-$ROOT/assets/status-line.svg}"

export PATH="$ROOT/tests/stubs:$PATH"
export TMUX="/tmp/tmux-screenshot"
export TMUX_USEFUL_OS_OVERRIDE=Darwin
export TMUX_USEFUL_NO_WATCHDOG=1
export MOCK_OPT_useful_batt_icons_ascii=on
export MOCK_OPT_useful_git_icon=""
export MOCK_OPT_useful_pane_icon=""
export MOCK_OPT_useful_spotify_icon="♪"

# Dogfood the plugin's own cell-width helper for layout.
# shellcheck source-path=SCRIPTDIR
# shellcheck source=../scripts/helpers.sh
source "$ROOT/scripts/helpers.sh"

CHAR_W=100         # tenths of a px per cell. Deliberately generous: real 14px
                   # monospace faces advance ~8.4-9.0px, so nothing can clip on
                   # the right no matter which face the reader has. Rows also
                   # carry textLength, which browsers (i.e. GitHub) honour to
                   # pin the run to exactly this width.
FONT_SIZE=14
BAR_H=30
CAP_H=18
ROW_GAP=24
PAD_X=14
GAP_MIN=6

LEFT_SESSION="  dev "
LEFT_BRANCH="main"
CLOCK=" 14:32"

xml_escape() {
    local s="$1"
    s="${s//&/&amp;}"; s="${s//</&lt;}"; s="${s//>/&gt;}"
    printf '%s' "$s"
}

# Convert tmux markup into <tspan> runs -> SPANS.
markup_to_tspans() {
    local text="$1" out="" pre rest tok colour="#d8dee9"
    while [ -n "$text" ]; do
        case "$text" in
            *'#['*)
                pre="${text%%#\[*}"
                rest="${text#*#\[}"
                tok="${rest%%\]*}"
                text="${rest#*\]}"
                [ -n "$pre" ] && out="$out<tspan fill=\"$colour\">$(xml_escape "$pre")</tspan>"
                case "$tok" in
                    fg=default) colour="#d8dee9" ;;
                    fg=*)       colour="${tok#fg=}" ;;
                esac
                ;;
            *)
                out="$out<tspan fill=\"$colour\">$(xml_escape "$text")</tspan>"
                text=""
                ;;
        esac
    done
    SPANS="$out"
}

# Run the real driver -> BODY (markup).
render_body() {
    local segments="$1" cache
    cache="$(mktemp -d)"
    BODY=$(TMUX_USEFUL_CACHE_DIR="$cache" "$ROOT/bin/useful-status" \
             --render=tmux --segments="$segments" 2>/dev/null)
    rm -rf "$cache"
}

captions=(); bodies=(); rights=()

add_row() {
    local caption="$1" segments="$2"
    render_body "$segments"
    captions+=("$caption")
    bodies+=("$BODY")
    # Plain text of the right chunk, for width maths.
    rights+=("$(useful_render plain "$BODY")$CLOCK")
}

# ------------------------------------------------------------------ scenarios

# 1. Healthy — the design contract. system/spotify/pane render nothing at all;
#    battery and weather are ambient by default and stay dim.
export MOCK_LOADAVG="{ 0.6 0.5 0.4 }" MOCK_NCPU=10
export MOCK_MEM_FREE=72 MOCK_DISK_PCT=34
export MOCK_BATT_AC=1 MOCK_BATT_PCT=98
export MOCK_PANE_COMMAND=zsh MOCK_SPOTIFY_RUNNING=0
export MOCK_CURL_OUTPUT="☀ 21°C"
add_row "healthy — system, git, spotify and pane all stay silent" \
        "pane,spotify,system,weather,battery"

# 2. Warn bands, plus the situational segments.
export MOCK_LOADAVG="{ 8.2 7.0 6.0 }" MOCK_NCPU=10
export MOCK_MEM_FREE=18 MOCK_DISK_PCT=84
export MOCK_BATT_AC=0 MOCK_BATT_PCT=34
export MOCK_PANE_COMMAND=nvim
export MOCK_SPOTIFY_RUNNING=1 MOCK_SPOTIFY_TRACK="Nils Frahm · Says"
export MOCK_CURL_OUTPUT="☁ 18°C"
add_row "warning — load, memory, disk and battery cross their thresholds" \
        "pane,spotify,system,weather,battery"

# 3. Critical — the "!" prefix keeps state legible without colour.
export MOCK_LOADAVG="{ 16.0 14.0 12.0 }" MOCK_NCPU=10
export MOCK_MEM_FREE=4 MOCK_DISK_PCT=97
export MOCK_BATT_AC=0 MOCK_BATT_PCT=9
export MOCK_PANE_COMMAND=docker
export MOCK_SPOTIFY_RUNNING=0
export MOCK_CURL_OUTPUT="☁ 18°C"
add_row "critical — the \"!\" prefix keeps state legible without colour" \
        "pane,system,weather,battery"

# ------------------------------------------------------------------ layout
useful_display_width "$LEFT_SESSION$LEFT_BRANCH"
left_cells=$USEFUL_WIDTH

total_cells=0
for r in "${rights[@]}"; do
    useful_display_width "$r"
    cand=$(( left_cells + GAP_MIN + USEFUL_WIDTH ))
    [ "$cand" -gt "$total_cells" ] && total_cells=$cand
done

WIDTH=$(( (total_cells * CHAR_W) / 10 + 2 * PAD_X ))
ROW_TOTAL=$(( BAR_H + CAP_H + ROW_GAP ))
HEIGHT=$(( ${#captions[@]} * ROW_TOTAL - ROW_GAP + 8 ))

{
printf '<svg xmlns="http://www.w3.org/2000/svg" width="%d" height="%d" viewBox="0 0 %d %d" font-family="ui-monospace, SFMono-Regular, Menlo, Consolas, monospace">\n' \
    "$WIDTH" "$HEIGHT" "$WIDTH" "$HEIGHT"

y=4
i=0
while [ "$i" -lt "${#captions[@]}" ]; do
    useful_display_width "${rights[$i]}"
    pad=$(( total_cells - left_cells - USEFUL_WIDTH ))
    [ "$pad" -lt 1 ] && pad=1

    printf '<text x="2" y="%d" font-size="11" fill="#7b8696">%s</text>\n' \
        "$(( y + 11 ))" "$(xml_escape "${captions[$i]}")"
    printf '<rect x="0" y="%d" width="%d" height="%d" rx="6" fill="#2e3440"/>\n' \
        "$(( y + CAP_H ))" "$WIDTH" "$BAR_H"
    printf '<text x="%d" y="%d" font-size="%d" textLength="%d" lengthAdjust="spacing" xml:space="preserve">' \
        "$PAD_X" "$(( y + CAP_H + 20 ))" "$FONT_SIZE" "$(( (total_cells * CHAR_W) / 10 ))"
    printf '<tspan fill="#88c0d0" font-weight="bold">%s</tspan>' "$(xml_escape "$LEFT_SESSION")"
    printf '<tspan fill="#7b8696">%s</tspan>' "$(xml_escape "$LEFT_BRANCH")"
    printf '<tspan>%*s</tspan>' "$pad" ""
    markup_to_tspans "${bodies[$i]}"
    printf '%s' "$SPANS"
    printf '<tspan fill="#88c0d0">%s</tspan>' "$(xml_escape "$CLOCK")"
    printf '</text>\n'

    y=$(( y + ROW_TOTAL ))
    i=$(( i + 1 ))
done

printf '</svg>\n'
} > "$OUT"

printf 'wrote %s  (%d x %d, %d cells wide)\n' "$OUT" "$WIDTH" "$HEIGHT" "$total_cells"
