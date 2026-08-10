#!/usr/bin/env bash
# Shared helpers for tmux-useful-status-line scripts.

# Force a UTF-8 locale so bash's ${var:offset:length} slices on character
# boundaries instead of bytes. Without this, CJK/RTL track names get cut
# mid-byte during the Spotify slide, producing mojibake.
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8*|*utf8*) ;;
    *)
        if locale -a 2>/dev/null | grep -qi '^C\.UTF-8$'; then
            export LC_ALL=C.UTF-8
        elif locale -a 2>/dev/null | grep -qi '^en_US\.UTF-8$'; then
            export LC_ALL=en_US.UTF-8
        fi
        ;;
esac

# Single source of truth for the version. Bump this when tagging a release;
# bin/useful-status --version reports it.
# shellcheck disable=SC2034  # read by bin/useful-status
USEFUL_VERSION="0.2.0-dev"

# Portable file-mtime in seconds. BSD/macOS uses `stat -f %m`; GNU's `-f`
# is `--file-system` mode and breaks here, so we dispatch by REAL uname,
# not by TMUX_USEFUL_OS_OVERRIDE (the override only swaps script logic;
# the underlying `stat` binary still has its native syntax).
file_mtime() {
    case "$(uname -s 2>/dev/null)" in
        Darwin|*BSD*) stat -f %m "$1" 2>/dev/null ;;
        *)            stat -c %Y "$1" 2>/dev/null ;;
    esac
}

# OS detection. Tests can override with TMUX_USEFUL_OS_OVERRIDE to exercise
# Linux code paths on a macOS CI runner.
useful_os() {
    printf "%s" "${TMUX_USEFUL_OS_OVERRIDE:-$(uname -s 2>/dev/null)}"
}

is_darwin() { [ "$(useful_os)" = "Darwin" ]; }
is_linux()  { [ "$(useful_os)" = "Linux" ]; }

# --------------------------------------------------------------------- config
#
# Every @useful-* option the segments read, fetched in ONE tmux round-trip.
#
# The naive `tmux show-option -gqv` costs a fork per option — 14 of them in
# system.sh alone, ~31 across a warm status refresh. Instead we expand every
# option in a single `display-message -p` format string. Format expansion
# returns values byte-exact: no shell quoting (unlike `show-options -g`, which
# emits `\t`/`\"`/`\\` escapes that would need an error-prone unquoter) and no
# recursive re-expansion of `#{...}` or `#[...]` appearing inside a value.
#
# tests/test_config.bats asserts this list covers every literal
# get_tmux_option call site, so adding an option to a segment without
# registering it here fails CI rather than silently falling back to a fork.
USEFUL_OPT_MANIFEST="
@useful-batt-crit
@useful-batt-full-pct
@useful-batt-icon-charging
@useful-batt-icon-empty
@useful-batt-icon-full
@useful-batt-icon-high
@useful-batt-icon-low
@useful-batt-icon-mid
@useful-batt-icons-ascii
@useful-batt-show-when
@useful-batt-warn
@useful-battery-enabled
@useful-cache-dir
@useful-color-accent
@useful-color-crit
@useful-color-dim
@useful-color-ok
@useful-color-warn
@useful-cpu-style
@useful-disk-crit
@useful-disk-crit-prefix
@useful-disk-warn
@useful-git-dirty-mark
@useful-git-enabled
@useful-git-icon
@useful-git-max-branch-len
@useful-git-skip-untracked
@useful-icon-disk
@useful-icon-load
@useful-icon-mem
@useful-load-crit
@useful-load-crit-prefix
@useful-load-warn
@useful-mem-crit
@useful-mem-crit-prefix
@useful-mem-warn
@useful-pane-enabled
@useful-pane-hide
@useful-pane-icon
@useful-pane-max-len
@useful-render
@useful-spotify-enabled
@useful-spotify-icon
@useful-spotify-max-len
@useful-spotify-scroll
@useful-spotify-scroll-duration
@useful-spotify-scroll-dwell
@useful-spotify-separator
@useful-segments
@useful-system-enabled
@useful-system-show-when
@useful-theme
@useful-weather-enabled
@useful-weather-format
@useful-weather-location
@useful-weather-refresh
@useful-warn-prefix
@useful-weather-stale
"

# Set to 1 once the batch fetch has been attempted. Re-sourcing helpers.sh
# resets it, which is what lets tests re-evaluate against new mock options.
useful_config_loaded=0
# 1 when the batch fetch succeeded and USEFUL_OPT_* holds the snapshot;
# 0 when it failed (no server, no session) and we must read per-option.
useful_config_batch_ok=0
# " @useful-a @useful-b ... " — space-padded for O(1) `case` membership tests.
useful_manifest_flat=""

# Unit Separator. Cannot appear in a tmux option set through normal means,
# and is not produced by any format we expand.
useful_config_sep=$'\037'

# Snapshot every manifest option plus the pane context in one call. Runs at
# source time (see the bottom of this file) so the values live in the main
# shell — every later `$(color_ok)`-style command substitution then inherits
# them instead of forking tmux inside its own subshell.
useful_config_load() {
    [ "$useful_config_loaded" = "1" ] && return 0
    useful_config_loaded=1

    local name fmt="" out had_noglob=0 i=0 var
    useful_manifest_flat=" "
    for name in $USEFUL_OPT_MANIFEST; do
        fmt="${fmt}#{${name}}${useful_config_sep}"
        useful_manifest_flat="${useful_manifest_flat}${name} "
    done
    # Pane context rides along for free — git.sh and pane.sh would each
    # otherwise spend a `tmux display -p` fork on it.
    fmt="${fmt}#{pane_current_path}${useful_config_sep}#{pane_current_command}${useful_config_sep}END"

    # `|| out=""` matters: without it a failing tmux makes the assignment
    # return non-zero, which aborts the caller under `set -e`.
    out=$(tmux display-message -p "$fmt" 2>/dev/null) || out=""
    # A bare "END" (or empty) means no server/session answered. Fall back to
    # per-option reads so a detached server still resolves options correctly.
    case "$out" in
        *"${useful_config_sep}END") ;;
        *) return 0 ;;
    esac

    # Guard 1: a tmux too old to expand #{@user-option} may echo the token
    # back verbatim. That is the dangerous shape — "@useful-mem-crit" would
    # become the literal string "#{@useful-mem-crit}", and the numeric
    # comparisons in system.sh would fail on it. Refuse the whole batch.
    case "$out" in
        *'#{@'*) return 0 ;;
    esac

    # Split on the separator. Word splitting on a non-whitespace IFS preserves
    # empty fields, which is what makes "option is unset" round-trip.
    case "$-" in *f*) had_noglob=1 ;; esac
    set -f
    local oldifs="$IFS"
    IFS="$useful_config_sep"
    # shellcheck disable=SC2206  # deliberate split on useful_config_sep
    local fields=( $out )
    IFS="$oldifs"
    [ "$had_noglob" -eq 0 ] && set +f

    local any_set=0
    for name in $USEFUL_OPT_MANIFEST; do
        var="USEFUL_OPT_${name#@}"
        var="${var//-/_}"
        eval "$var=\"\${fields[\$i]}\""
        # `if` rather than `&&`: a bare `&&` leaves the loop's exit status at 1
        # whenever the last option is empty, which aborts the caller under
        # `set -e` — and an empty last option is the common case.
        if eval "[ -n \"\$$var\" ]"; then any_set=1; fi
        i=$(( i + 1 ))
    done
    USEFUL_PANE_PATH="${fields[$i]}"
    USEFUL_PANE_COMMAND="${fields[$(( i + 1 ))]}"

    # Guard 2: the other way #{@user-option} can fail is by expanding to
    # nothing, which is indistinguishable from "the user configured nothing"
    # — and would silently ignore every @useful-* setting. If the batch came
    # back completely empty, one listing call settles it. This costs a second
    # fork only for users who have set no options at all, where the answer is
    # the same either way.
    if [ "$any_set" -eq 0 ] && tmux show-options -g 2>/dev/null | grep -q '^@useful-'; then
        return 0
    fi

    useful_config_batch_ok=1
}

# Drop the snapshot so the next lookup re-reads. Tests use this when they
# change a mock option after helpers.sh has already been sourced.
useful_config_reset() {
    local name var
    for name in $USEFUL_OPT_MANIFEST; do
        var="USEFUL_OPT_${name#@}"
        var="${var//-/_}"
        unset "$var"
    done
    unset USEFUL_PANE_PATH USEFUL_PANE_COMMAND
    useful_config_loaded=0
    useful_config_batch_ok=0
    useful_config_load
}

get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local val var

    useful_config_load

    if [ "$useful_config_batch_ok" = "1" ]; then
        case "$useful_manifest_flat" in
            *" $option "*)
                var="USEFUL_OPT_${option#@}"
                var="${var//-/_}"
                eval "val=\"\${$var:-}\""
                ;;
            # Not in the manifest (a caller outside this repo, or a name added
            # to a segment without registering it). Correct, just not free.
            *) val=$(tmux show-option -gqv "$option" 2>/dev/null) ;;
        esac
    else
        val=$(tmux show-option -gqv "$option" 2>/dev/null)
    fi

    if [ -z "$val" ]; then
        echo "$default_value"
    else
        echo "$val"
    fi
}

# Active pane's working directory / foreground command. Both come from the
# config snapshot when tmux answered; the direct calls are the fallback for a
# detached server, and TMUX_PANE_CURRENT_PATH lets a caller inject a cwd.
useful_pane_path() {
    if [ -n "${TMUX_PANE_CURRENT_PATH:-}" ]; then
        printf "%s" "$TMUX_PANE_CURRENT_PATH"
        return
    fi
    useful_config_load
    if [ "$useful_config_batch_ok" = "1" ]; then
        printf "%s" "${USEFUL_PANE_PATH:-}"
        return
    fi
    # `|| true`: these are getters whose contract is "print a value or
    # nothing", so a tmux that will not answer must not fail the caller.
    tmux display -p '#{pane_current_path}' 2>/dev/null || true
}

useful_pane_command() {
    useful_config_load
    if [ "$useful_config_batch_ok" = "1" ]; then
        printf "%s" "${USEFUL_PANE_COMMAND:-}"
        return
    fi
    tmux display -p '#{pane_current_command}' 2>/dev/null || true
}

# Ask the host to redraw its status line. tmux pushes; other hosts poll on
# their own interval, so this is a no-op there.
useful_request_redraw() {
    tmux refresh-client -S 2>/dev/null || true
}

# Cache helper: prints cache contents to stdout and exits 0 if fresh.
# Usage: cache_check "$CACHE_FILE" "$MAX_AGE_SEC" || run_and_cache
cache_check() {
    local file="$1"
    local max_age="$2"
    [ -f "$file" ] || return 1
    local mtime age
    mtime=$(file_mtime "$file")
    [ -z "$mtime" ] && return 1
    age=$(( $(date +%s) - mtime ))
    [ "$age" -lt "$max_age" ] || return 1
    cat "$file"
    return 0
}

# Default palette = Nord. Other themes are selected via @useful-theme.
# Individual @useful-color-* options always win over the theme's defaults.
default_color_ok="#a3be8c"
default_color_warn="#ebcb8b"
default_color_crit="#bf616a"
default_color_accent="#b48ead"
default_color_dim="#7b8696"

# Resolve @useful-theme. Supports Ghostty-style "dark:X,light:Y" syntax —
# auto-switches with the system appearance. Cached for 60s because the
# `defaults read` call costs ~50ms on macOS.
useful_resolve_theme() {
    local raw cache_file appearance now mtime
    raw=$(get_tmux_option "@useful-theme" "")
    case "$raw" in
        *dark:*light:*|*light:*dark:*)
            # Auto mode. Detect appearance with caching.
            cache_file="$(useful_cache_dir)/appearance"
            now=$(date +%s)
            appearance=""
            if [ -f "$cache_file" ]; then
                mtime=$(file_mtime "$cache_file" 2>/dev/null || echo 0)
                if [ -n "$mtime" ] && [ "$((now - mtime))" -lt 60 ]; then
                    appearance=$(cat "$cache_file")
                fi
            fi
            if [ -z "$appearance" ]; then
                case "$(useful_os)" in
                    Darwin)
                        if defaults read -g AppleInterfaceStyle 2>/dev/null | grep -qi dark; then
                            appearance=dark
                        else
                            appearance=light
                        fi
                        ;;
                    *)
                        # Linux: best-effort guess via $COLORFGBG (high bg value = light).
                        case "${COLORFGBG:-}" in
                            *\;1[0-5]) appearance=light ;;
                            *) appearance=dark ;;
                        esac
                        ;;
                esac
                printf "%s" "$appearance" >"$cache_file" 2>/dev/null
            fi
            # Pick the matching half. Format: "dark:NAME,light:NAME" (order-agnostic).
            local part
            for part in ${raw//,/ }; do
                case "$part" in
                    "${appearance}:"*) printf "%s" "${part#*:}"; return ;;
                esac
            done
            ;;
        *)
            printf "%s" "$raw"
            ;;
    esac
}

# Cache directory: namespaced per UID so multi-user hosts don't collide, and
# per tmux socket so multiple servers on the same host can't stomp each other.
useful_cache_dir() {
    local override
    override=$(get_tmux_option "@useful-cache-dir" "")
    if [ -n "$override" ]; then
        printf "%s" "$override"
        return
    fi
    if [ -n "${TMUX_USEFUL_CACHE_DIR:-}" ]; then
        printf "%s" "$TMUX_USEFUL_CACHE_DIR"
        return
    fi
    local base="${TMPDIR:-/tmp}"
    # Strip trailing slash for predictable concatenation.
    base="${base%/}"
    local socket_id=""
    if [ -n "${TMUX:-}" ]; then
        socket_id=$(printf "%s" "${TMUX%%,*}" | shasum 2>/dev/null | cut -c1-8)
    fi
    local dir="$base/tmux-useful-${UID:-$(id -u)}-${socket_id:-default}"
    mkdir -p "$dir" 2>/dev/null
    printf "%s" "$dir"
}

color_ok() { get_tmux_option "@useful-color-ok" "$default_color_ok"; }
color_warn() { get_tmux_option "@useful-color-warn" "$default_color_warn"; }
color_crit() { get_tmux_option "@useful-color-crit" "$default_color_crit"; }
color_accent() { get_tmux_option "@useful-color-accent" "$default_color_accent"; }
color_dim() { get_tmux_option "@useful-color-dim" "$default_color_dim"; }

# Per-segment enable/disable. Returns 0 if enabled (default), 1 if disabled.
segment_enabled() {
    local seg="$1"
    local val
    val=$(get_tmux_option "@useful-${seg}-enabled" "on")
    case "$val" in
        off|false|0|no) return 1 ;;
        *) return 0 ;;
    esac
}

# Take the config snapshot in the main shell, before anything runs inside a
# command substitution. Then load the theme presets, which read @useful-theme
# and (in auto mode) write through useful_cache_dir — both defined above.
useful_config_load

# Theme presets live in their own file — pure data, easier to scan.
# shellcheck source=themes.sh
source "$(dirname "${BASH_SOURCE[0]}")/themes.sh"

# --------------------------------------------------------------------- width
#
# Terminal layout is measured in CELLS, not characters. A CJK ideograph or an
# emoji occupies two; a combining mark occupies none. Truncating with ${#s} /
# ${s:0:n} therefore overshoots badly — a 24-character branch name can occupy
# 40 cells and push the rest of the status line off the terminal.
#
# helpers.sh already forces a UTF-8 locale so those slices land on character
# boundaries rather than byte boundaries. That fixes bytes-vs-characters; this
# section fixes characters-vs-cells, which is the one that governs layout.
#
# bash 3.2 (what macOS ships) cannot hand us a codepoint: printf '%d' "'X"
# returns the first BYTE, signed. So we decode UTF-8 ourselves, slicing
# bytewise under a function-local LC_ALL=C — bash re-reads the locale on
# assignment and restores it when the function returns.

# Decode the UTF-8 sequence at byte offset $2 of $1.
# Sets USEFUL_CP (codepoint) and USEFUL_CP_LEN (bytes consumed).
# Assumes the caller has already switched to LC_ALL=C.
useful_utf8_decode() {
    local s="$1" i="$2" ch b0 b1 b2 b3
    ch="${s:$i:1}"
    if [ -z "$ch" ]; then USEFUL_CP=0; USEFUL_CP_LEN=1; return; fi
    printf -v b0 '%d' "'$ch"
    [ "$b0" -lt 0 ] && b0=$(( b0 + 256 ))
    if [ "$b0" -lt 192 ]; then
        # ASCII, or a stray continuation byte we step over rather than choke on.
        USEFUL_CP=$b0; USEFUL_CP_LEN=1
    elif [ "$b0" -lt 224 ]; then
        printf -v b1 '%d' "'${s:$((i+1)):1}"; [ "$b1" -lt 0 ] && b1=$(( b1 + 256 ))
        USEFUL_CP=$(( ((b0 & 31) << 6) | (b1 & 63) )); USEFUL_CP_LEN=2
    elif [ "$b0" -lt 240 ]; then
        printf -v b1 '%d' "'${s:$((i+1)):1}"; [ "$b1" -lt 0 ] && b1=$(( b1 + 256 ))
        printf -v b2 '%d' "'${s:$((i+2)):1}"; [ "$b2" -lt 0 ] && b2=$(( b2 + 256 ))
        USEFUL_CP=$(( ((b0 & 15) << 12) | ((b1 & 63) << 6) | (b2 & 63) )); USEFUL_CP_LEN=3
    else
        printf -v b1 '%d' "'${s:$((i+1)):1}"; [ "$b1" -lt 0 ] && b1=$(( b1 + 256 ))
        printf -v b2 '%d' "'${s:$((i+2)):1}"; [ "$b2" -lt 0 ] && b2=$(( b2 + 256 ))
        printf -v b3 '%d' "'${s:$((i+3)):1}"; [ "$b3" -lt 0 ] && b3=$(( b3 + 256 ))
        USEFUL_CP=$(( ((b0 & 7) << 18) | ((b1 & 63) << 12) | ((b2 & 63) << 6) | (b3 & 63) ))
        USEFUL_CP_LEN=4
    fi
}

# Cells occupied by codepoint $1 -> USEFUL_CW (0, 1 or 2).
#
# Every branch is a CLOSED interval on purpose. A range table scanned with
# early returns has to stay sorted or later ranges become unreachable; closed
# intervals make the table order-independent, so a future edit cannot
# introduce that bug silently.
useful_cp_width() {
    local cp="$1"
    if   [ "$cp" -lt 768 ];                              then USEFUL_CW=1  # ASCII + Latin-1 fast path
    elif [ "$cp" -ge 768 ]    && [ "$cp" -le 879 ];      then USEFUL_CW=0  # U+0300-036F combining
    elif [ "$cp" -eq 8205 ];                             then USEFUL_CW=0  # U+200D ZWJ
    elif [ "$cp" -ge 65024 ]  && [ "$cp" -le 65039 ];    then USEFUL_CW=0  # U+FE00-FE0F variation selectors
    elif [ "$cp" -ge 4352 ]   && [ "$cp" -le 4447 ];     then USEFUL_CW=2  # U+1100-115F Hangul Jamo
    elif [ "$cp" -ge 11904 ]  && [ "$cp" -le 12350 ];    then USEFUL_CW=2  # U+2E80-303E CJK radicals/symbols
    elif [ "$cp" -ge 12353 ]  && [ "$cp" -le 19903 ];    then USEFUL_CW=2  # U+3041-4DBF kana .. CJK ext A
    elif [ "$cp" -ge 19968 ]  && [ "$cp" -le 42191 ];    then USEFUL_CW=2  # U+4E00-A4CF CJK unified + Yi
    elif [ "$cp" -ge 43360 ]  && [ "$cp" -le 43391 ];    then USEFUL_CW=2  # U+A960-A97F Hangul Jamo ext-A
    elif [ "$cp" -ge 44032 ]  && [ "$cp" -le 55203 ];    then USEFUL_CW=2  # U+AC00-D7A3 Hangul syllables
    elif [ "$cp" -ge 63744 ]  && [ "$cp" -le 64255 ];    then USEFUL_CW=2  # U+F900-FAFF CJK compat
    elif [ "$cp" -ge 65040 ]  && [ "$cp" -le 65049 ];    then USEFUL_CW=2  # U+FE10-FE19 vertical forms
    elif [ "$cp" -ge 65072 ]  && [ "$cp" -le 65135 ];    then USEFUL_CW=2  # U+FE30-FE6F CJK compat forms
    elif [ "$cp" -ge 65280 ]  && [ "$cp" -le 65376 ];    then USEFUL_CW=2  # U+FF00-FF60 fullwidth
    elif [ "$cp" -ge 65504 ]  && [ "$cp" -le 65510 ];    then USEFUL_CW=2  # U+FFE0-FFE6 fullwidth signs
    elif [ "$cp" -ge 127744 ] && [ "$cp" -le 983039 ];   then USEFUL_CW=2  # U+1F300-EFFFF emoji + astral CJK
    else                                                      USEFUL_CW=1
    fi
    # Deliberately NOT wide: U+2580-259F block elements (the CPU bar glyphs),
    # U+E000-F8FF and U+F0000+ private use (Nerd Font icons). Terminals render
    # all of those single-width; calling them wide would under-fill the bar.
}

# Sets USEFUL_WIDTH to the number of cells $1 occupies.
useful_display_width() {
    local LC_ALL=C
    # prev starts at 0, not 1: there is no glyph before the first character,
    # so a leading U+FE0F must not promote anything.
    local s="$1" n i=0 w=0 prev=0
    n=${#s}
    while [ "$i" -lt "$n" ]; do
        useful_utf8_decode "$s" "$i"
        i=$(( i + USEFUL_CP_LEN ))
        useful_cp_width "$USEFUL_CP"
        # U+FE0F requests emoji presentation, widening the glyph before it.
        if [ "$USEFUL_CP" -eq 65039 ] && [ "$prev" -eq 1 ]; then
            w=$(( w + 1 ))
        fi
        w=$(( w + USEFUL_CW ))
        prev=$USEFUL_CW
    done
    USEFUL_WIDTH=$w
}

# Extract the run of $1 beginning at cell offset $2 and spanning at most $3
# cells. Sets USEFUL_WINDOW, plus USEFUL_WINDOW_CUT_HEAD / _CUT_TAIL to 1 when
# content was dropped before / after the window. Never splits a character.
# shellcheck disable=SC2034  # CUT_HEAD/CUT_TAIL are read by callers (spotify.sh)
useful_window() {
    local LC_ALL=C
    local s="$1" start="$2" max="$3"
    local n i=0 acc=0 taken=0 out="" chunk prev=0 cw
    USEFUL_WINDOW=""; USEFUL_WINDOW_CUT_HEAD=0; USEFUL_WINDOW_CUT_TAIL=0
    n=${#s}
    [ "$max" -lt 1 ] && return
    while [ "$i" -lt "$n" ]; do
        useful_utf8_decode "$s" "$i"
        chunk="${s:$i:$USEFUL_CP_LEN}"
        i=$(( i + USEFUL_CP_LEN ))
        useful_cp_width "$USEFUL_CP"
        cw=$USEFUL_CW
        if [ "$USEFUL_CP" -eq 65039 ] && [ "$prev" -eq 1 ]; then
            cw=1   # the selector itself is zero-width; it adds a cell to the previous glyph
        fi
        prev=$USEFUL_CW
        if [ "$acc" -lt "$start" ]; then
            acc=$(( acc + cw )); USEFUL_WINDOW_CUT_HEAD=1; continue
        fi
        if [ $(( taken + cw )) -gt "$max" ]; then USEFUL_WINDOW_CUT_TAIL=1; break; fi
        out="$out$chunk"
        taken=$(( taken + cw ))
    done
    USEFUL_WINDOW="$out"
}

# Sets USEFUL_TRUNC to $1 fitted into $2 cells, appending $3 (default "…")
# when it had to cut. The ellipsis is charged against the budget.
# shellcheck disable=SC2034  # USEFUL_TRUNC is read by callers (git.sh, pane.sh)
useful_truncate() {
    local s="$1" max="$2" ell="${3-…}" ew
    useful_display_width "$s"
    if [ "$USEFUL_WIDTH" -le "$max" ]; then USEFUL_TRUNC="$s"; return; fi
    useful_display_width "$ell"
    ew=$USEFUL_WIDTH
    # No room even for the marker: emit nothing rather than overflow by a cell.
    if [ "$max" -lt "$ew" ]; then USEFUL_TRUNC=""; return; fi
    useful_window "$s" 0 $(( max - ew ))
    USEFUL_TRUNC="$USEFUL_WINDOW$ell"
}

# -------------------------------------------------------------------- render
#
# Segments always emit tmux markup; it is the internal wire format. Hosts that
# are not tmux get it translated here, on the way out. That keeps the six
# segment scripts host-agnostic without threading a renderer through all 16
# of their colour sites.
#
# The markup we emit is a closed set — "#[fg=COLOUR]" and "#[fg=default]" —
# so this is a total mapping, not a general tmux-format parser.

# Resolve one tmux attribute token into an ANSI SGR sequence, into $ANSI.
# Sets a global rather than echoing so translation stays fork-free.
useful_ansi_attr() {
    local attr="$1" hex n
    ANSI=""
    case "$attr" in
        fg=default) ANSI=$'\033[39m' ;;
        fg=#??????)
            hex="${attr#fg=#}"
            ANSI=$'\033'"[38;2;$((16#${hex:0:2}));$((16#${hex:2:2}));$((16#${hex:4:2}))m"
            ;;
        fg=colour*|fg=color*)
            n="${attr#fg=colo}"; n="${n#u}"; n="${n#r}"
            case "$n" in
                ''|*[!0-9]*) ANSI="" ;;
                *) ANSI=$'\033'"[38;5;${n}m" ;;
            esac
            ;;
        fg=black)   ANSI=$'\033[30m' ;;
        fg=red)     ANSI=$'\033[31m' ;;
        fg=green)   ANSI=$'\033[32m' ;;
        fg=yellow)  ANSI=$'\033[33m' ;;
        fg=blue)    ANSI=$'\033[34m' ;;
        fg=magenta) ANSI=$'\033[35m' ;;
        fg=cyan)    ANSI=$'\033[36m' ;;
        fg=white)   ANSI=$'\033[37m' ;;
        *)          ANSI="" ;;
    esac
}

# useful_render <tmux|ansi|plain> <text>
useful_render() {
    local mode="$1" text="$2" out="" pre rest tok
    [ "$mode" = "tmux" ] && { printf "%s" "$text"; return; }
    while [ -n "$text" ]; do
        case "$text" in
            *'#['*)
                pre="${text%%#\[*}"
                rest="${text#*#\[}"
                tok="${rest%%\]*}"
                text="${rest#*\]}"
                out="$out$pre"
                if [ "$mode" = "ansi" ]; then
                    useful_ansi_attr "$tok"
                    out="$out$ANSI"
                fi
                ;;
            *) out="$out$text"; text="" ;;
        esac
    done
    printf "%s" "$out"
}

# Severity of a rendered segment, inferred from which palette tone it used.
# Lets JSON consumers (waybar, i3blocks) style by state without the segments
# having to report it separately.
useful_severity() {
    local text="$1"
    case "$text" in
        *"#[fg=$(color_crit)]"*) printf "critical" ;;
        *"#[fg=$(color_warn)]"*) printf "warning" ;;
        *"#[fg="*)               printf "normal" ;;
        *)                       printf "none" ;;
    esac
}

# Minimal JSON string escaping — enough for the values segments can produce
# (quotes, backslashes, and control characters).
useful_json_escape() {
    local s="$1"
    s="${s//\\/\\\\}"
    s="${s//\"/\\\"}"
    s="${s//	/\\t}"
    s="${s//$'\n'/\\n}"
    printf "%s" "$s"
}

# Marks helpers as present in THIS shell. Deliberately not exported: a segment
# run as a subprocess must still source helpers itself. Sourcing this file
# again always re-runs everything above, which is how tests re-evaluate a
# changed @useful-theme.
# shellcheck disable=SC2034  # read by the guard at the top of each segment
USEFUL_HELPERS_LOADED=1
