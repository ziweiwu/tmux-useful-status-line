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
USEFUL_VERSION="0.3.0"

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

# Short stable digest of $1, for cache keys.
#
# `shasum` is a perl script, not a coreutils binary: musl distros (Alpine,
# anything on busybox) ship `sha1sum` instead, and a Debian without perl ships
# neither. When the call failed, the old inline `| shasum | cut` produced an
# EMPTY key — and an empty key is not a degraded key, it is a COLLIDING one:
# every repo shared the single cache file "git-", so switching panes between
# two repos showed the wrong branch for the whole TTL, and every
# @useful-weather-location shared one "weather-" entry.
#
# Falls back through sha1sum to cksum (POSIX, present everywhere), and finally
# to the input itself with path separators flattened — long and ugly, but
# still unique, which is the only property a cache key owes us.
useful_hash() {
    local s="$1" out
    out=$(printf "%s" "$s" | { shasum 2>/dev/null || sha1sum 2>/dev/null || cksum 2>/dev/null; } | cut -c1-8)
    case "$out" in
        ''|*[!0-9a-fA-F]*)
            out="${s//\//_}"
            out="${out//[^A-Za-z0-9_.-]/_}"
            ;;
    esac
    printf "%s" "$out"
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
@useful-batt-crit-prefix
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
@useful-contrast
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
@useful-timeout
@useful-timeout-total
@useful-weather-enabled
@useful-weather-format
@useful-weather-location
@useful-weather-max-len
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

# Numeric @useful-* option, validated.
#
# A typo'd threshold used to reach `[ x -ge y ]` raw: bash wrote "integer
# expression expected" to stderr, tmux's #() captures only stdout, and the
# segment silently vanished with no way for the user to tell why. Fall back to
# the documented default instead, and leave one line on stderr for anyone
# running the script by hand.
#
# Non-negative integers only — every numeric option here is a percentage, a
# cell budget or a duration. The 9-digit ceiling keeps values inside the range
# `[` can compare: bash rejects anything past 2^63-1 with exactly the opaque
# error we are trying to eliminate.
useful_int_option() {
    local option="$1" default="$2" val
    val=$(get_tmux_option "$option" "$default")
    case "$val" in
        ''|*[!0-9]*|??????????*)
            printf "useful-status: %s: '%s' is not an integer in 0-999999999; using %s\n" \
                "$option" "$val" "$default" >&2
            val="$default"
            ;;
    esac
    printf "%s" "$val"
}

# Icon @useful-* option, ready to concatenate.
#
# Two problems solved together. First, there was no way to turn an icon OFF:
# get_tmux_option treats "" as "unset" and hands back the default, so
# `set -g @useful-git-icon ""` silently kept the glyph. Clearing one now needs
# an explicit word, reusing the none/off/false/no vocabulary the crit-prefix
# options already speak.
#
# Second, the separating space is carried ON the icon rather than written into
# the format string. "%s %s" with an empty icon emits a doubled leading space;
# collapsing it here means every call site gets the empty case right for free.
useful_icon_option() {
    local val
    val=$(get_tmux_option "$1" "$2")
    case "$val" in
        none|off|false|no) ;;
        "")                ;;
        *)                 printf "%s " "$val" ;;
    esac
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

# ------------------------------------------------------------------ timeouts
#
# Every data source this plugin reads can block indefinitely, and several do so
# in practice: `df` on a stale NFS mount, `git status` on a network filesystem,
# `osascript` while Spotify is wedged, `pmset` during an IOKit hiccup. The
# driver runs all six segments serially in one process, so one stuck call
# freezes the entire status line — and the README's shell-prompt recipe wires
# the same binary into PS1/RPROMPT, where it freezes the prompt.
#
# Built from bash job control rather than delegating to timeout(1) when the
# platform has one. That dual-path design was tried and withdrawn: the two
# implementations disagreed about `0` (coreutils reads it as "no limit", a bare
# `sleep 0` watchdog reads it as "kill immediately") and about SIGKILL
# escalation (GNU timeout needs an explicit -k; BSD and busybox spell it
# differently or not at all). An escape hatch that works on Linux and breaks on
# macOS is worse than no escape hatch, and macOS — the platform most of this
# runs on — ships no timeout(1) anyway, so the fallback WAS the main path.

# Grace period between SIGTERM and SIGKILL.
USEFUL_TIMEOUT_KILL_AFTER=1

# Smallest slice the whole-run budget will hand out. See useful_timeout.
USEFUL_TIMEOUT_FLOOR=1

# Whole-run budget, in seconds. The per-call limit alone bounds each source but
# not their sum: system.sh guards four calls, git.sh three, spotify.sh two,
# battery.sh one, so a host where everything is wedged at once — the exact
# stale-NFS scenario this exists for — could still block 10 x @useful-timeout.
# Populated by useful_config_load; 0 disables the ceiling.
USEFUL_TIMEOUT_TOTAL=0

# useful_timeout <seconds> <command> [args...]
# Runs the command, killing it if it outruns the budget. Exit status is the
# command's own, or non-zero when it was killed — callers treat both the same
# way they already treat a failing data source.
useful_timeout() {
    local secs="$1"; shift
    # 0 means "no limit", and disables the whole-run ceiling with it: a user who
    # turns the bound off gets it off, not a different bound.
    if [ "$secs" = "0" ]; then
        "$@"
        return $?
    fi

    # SECONDS counts from process start and is a bash builtin, so the shared
    # deadline costs no fork — which matters, because this runs per data source.
    #
    # The budget SHRINKS later calls; it never cancels them. Refusing to run a
    # call once the clock was spent looked tidier and was wrong: the driver runs
    # segments in a fixed order, so a wedged `git` early in the list silenced a
    # perfectly healthy `battery` later in it — the status line went blank
    # because of a failure in an unrelated segment, which inverts the whole
    # "silent when healthy, loud when it isn't" contract and leaves the user
    # unable to tell the two apart. A healthy source answers in milliseconds, so
    # the floor costs nothing when things are fine and bounds the overrun when
    # they are not.
    if [ "${USEFUL_TIMEOUT_TOTAL:-0}" -gt 0 ]; then
        local remaining=$(( USEFUL_TIMEOUT_TOTAL - SECONDS ))
        if [ "$remaining" -lt "$secs" ]; then
            secs="$remaining"
            [ "$secs" -lt "$USEFUL_TIMEOUT_FLOOR" ] && secs="$USEFUL_TIMEOUT_FLOOR"
        fi
    fi

    local cmd_pid watch_pid rc had_monitor=0
    # Job control, so the child leads its own process group and the watchdog can
    # signal the whole tree. Killing just the direct child is not enough: it is
    # the GRANDchildren that keep the command-substitution pipe open, so
    # `pmset | awk` or `sh -c "sleep 5"` would still block for the full runtime
    # after its parent died.
    case "$-" in *m*) had_monitor=1 ;; esac
    set -m
    # `<&0` is load-bearing, not decoration. Bash redirects an asynchronous
    # command's stdin from /dev/null "in the absence of any explicit
    # redirections" — which silently ate the heredoc carrying spotify.sh's
    # AppleScript.
    "$@" <&0 &
    cmd_pid=$!
    [ "$had_monitor" -eq 0 ] && set +m
    # The watchdog MUST NOT inherit stdout. Callers run this inside $(...), and
    # a command substitution ends when the last writer closes the pipe, not
    # when the foreground child exits — a watchdog holding the pipe open would
    # make every guarded call wait out the full timeout.
    (
        sleep "$secs"
        kill -TERM "-$cmd_pid" 2>/dev/null
        # Then escalate. SIGTERM alone is a request, and a data source is free
        # to ignore it — wrapper scripts and anything with a graceful-shutdown
        # handler routinely do. Without this the `wait` below blocks forever on
        # a process that trapped TERM, which is precisely the hang the timeout
        # was added to prevent, and the child leaks as an orphan on top.
        sleep "$USEFUL_TIMEOUT_KILL_AFTER"
        kill -KILL "-$cmd_pid" 2>/dev/null
    ) >/dev/null 2>&1 &
    watch_pid=$!
    wait "$cmd_pid" 2>/dev/null
    rc=$?
    kill "$watch_pid" 2>/dev/null
    wait "$watch_pid" 2>/dev/null
    return "$rc"
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
    # A future mtime makes `age` negative, which passes any max_age test and
    # pins the entry as fresh forever. Clock skew, a VM restored from a
    # snapshot, or a hand-planted cache file all produce it. Treat "written in
    # the future" as stale and re-derive.
    [ "$age" -ge 0 ] || return 1
    [ "$age" -lt "$max_age" ] || return 1

    # A cache entry is markup we wrote — but not necessarily markup we finished
    # writing. A `tee` killed mid-write (a full disk, the timeout above firing,
    # a SIGKILL) leaves a colour run open, and tmux then bleeds that colour into
    # every segment drawn after it, for the whole TTL. Bit-rot, a truncated
    # write, or another process with access to the cache dir can put arbitrary
    # bytes in there too, and those went straight to the terminal.
    #
    # $(<file) rather than `cat`: a builtin read, one fork fewer on the path
    # taken by every warm refresh.
    local content probe
    content=$(<"$file")
    # An entry far longer than any status line could be is corrupt, not cached.
    # Recompute rather than paste it into the bar. ${#} is a builtin, so this
    # costs nothing on the warm path it guards. x4 leaves room for multi-byte
    # characters, which are counted here in bytes.
    [ "${#content}" -gt $(( USEFUL_MAX_CELLS * 4 )) ] && return 1
    content="${content//[[:cntrl:]]/ }"
    # The only markup this repo ever writes to a cache entry is "#[fg=...]".
    # Anything else in there did not come from us: a background block (banned
    # outright by AGENTS.md, and able to repaint the whole bar), or a "#{...}"
    # that tmux expands as a format. Sanitising the BYTES above is not enough,
    # because the danger is the markup, and cache contents are emitted verbatim
    # -- escaping them is not an option, since our own tokens must survive.
    # Recompute instead of pasting an entry we cannot account for.
    #
    # Removing our own token first is what makes the test a one-liner: what
    # remains of a well-formed entry has no "#[" left. A "##[" from
    # useful_escape survives correctly, leaving a bare "#" and no "#[".
    probe="${content//'#[fg='/}"
    case "$probe" in
        *'#['*|*'#{'*) return 1 ;;
    esac
    case "$content" in
        *'#[fg='*)
            case "$content" in
                *'#[fg=default]') ;;
                *) content="$content#[fg=default]" ;;
            esac
            ;;
    esac
    printf "%s" "$content"
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

# Only set when the directory we resolved turned out not to be ours; see below.
# Memoized so the hostile path does not leak a new temp dir per call.
USEFUL_CACHE_DIR_FALLBACK=""

# Cache directory: namespaced per UID so multi-user hosts don't collide, and
# per tmux socket so multiple servers on the same host can't stomp each other.
useful_cache_dir() {
    local dir override
    override=$(get_tmux_option "@useful-cache-dir" "")
    if [ -n "$override" ]; then
        dir="$override"
    elif [ -n "${TMUX_USEFUL_CACHE_DIR:-}" ]; then
        dir="$TMUX_USEFUL_CACHE_DIR"
    else
        local base="${TMPDIR:-/tmp}"
        # Strip trailing slash for predictable concatenation.
        base="${base%/}"
        local socket_id=""
        if [ -n "${TMUX:-}" ]; then
            socket_id=$(useful_hash "${TMUX%%,*}")
        fi
        dir="$base/tmux-useful-${UID:-$(id -u)}-${socket_id:-default}"
    fi

    # Create it for EVERY branch, not just the derived one. @useful-cache-dir
    # pointing at a directory that did not exist yet used to disable caching
    # outright and silently: `tee` failed to a stderr tmux discards, so the
    # segments still rendered while every cache write was lost. The visible
    # cost was weather.sh making a blocking network call on every single status
    # refresh, because its rate-limit stamp could not be written either.
    #
    # -m 700 rather than the umask default: the derived name is entirely
    # predictable, so on a shared /tmp this must not be a directory another
    # user can write into.
    # shellcheck disable=SC2174  # -m applying only to the deepest directory is
    # exactly what we want: the parents are ordinary paths like /tmp or $HOME,
    # whose modes are not ours to set. It is the leaf we must not share.
    mkdir -m 700 -p "$dir" 2>/dev/null

    # mkdir succeeds on a directory that already exists whoever owns it, so
    # having created it is not proof that it is ours. That matters because a
    # cache entry is markup pasted straight into the status line: a directory
    # somebody else can write is a directory that can write the status line.
    # Prefer a private temp dir over trusting it. Caching then lasts one
    # process instead of persisting, which is the right trade when the
    # alternative is honouring a planted entry.
    if [ ! -d "$dir" ] || [ ! -O "$dir" ]; then
        if [ -z "$USEFUL_CACHE_DIR_FALLBACK" ]; then
            USEFUL_CACHE_DIR_FALLBACK=$(mktemp -d 2>/dev/null) || USEFUL_CACHE_DIR_FALLBACK=""
        fi
        dir="$USEFUL_CACHE_DIR_FALLBACK"
    fi
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

# Whole-run timeout ceiling. Read here rather than at its definition because
# get_tmux_option needs the config snapshot above. Default 10s: comfortably
# more than any healthy refresh needs, comfortably less than the ~30s a fully
# wedged host could otherwise reach through ten independently-guarded calls.
USEFUL_TIMEOUT_TOTAL=$(useful_int_option "@useful-timeout-total" 10)

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
    local s="$1" i="$2" ch b0 b1 b2 b3 need k bb bc lo hi
    ch="${s:$i:1}"
    if [ -z "$ch" ]; then USEFUL_CP=0; USEFUL_CP_LEN=1; return; fi
    printf -v b0 '%d' "'$ch"
    [ "$b0" -lt 0 ] && b0=$(( b0 + 256 ))

    if [ "$b0" -lt 128 ]; then USEFUL_CP=$b0; USEFUL_CP_LEN=1; return; fi

    # Not a legal lead byte -> one bad byte, consumed alone. Terminals draw one
    # replacement glyph per undecodable byte, so consuming exactly one keeps the
    # cell count in step with what is actually painted.
    #   0x80-0xBF  stray continuation byte
    #   0xC0-0xC1  overlong two-byte forms, never valid
    #   0xF5-0xFF  past U+10FFFF, never valid
    # Trusting these as leads is what let a single 0xFF swallow the three ASCII
    # characters after it, under-counting the string by three cells and
    # overflowing the very budget useful_truncate exists to guarantee.
    if [ "$b0" -lt 194 ] || [ "$b0" -gt 244 ]; then
        USEFUL_CP=$b0; USEFUL_CP_LEN=1; return
    fi

    if   [ "$b0" -lt 224 ]; then need=1
    elif [ "$b0" -lt 240 ]; then need=2
    else                         need=3
    fi

    # The FIRST continuation byte has a narrower legal range for four of the
    # lead bytes (RFC 3629 / WHATWG). Accepting the full 0x80-0xBF there admits
    # overlong forms, UTF-16 surrogates, and codepoints past U+10FFFF — none of
    # which a compliant terminal decodes as one glyph. It substitutes one
    # replacement per bad byte, so "\xE0\x80\x80" is three cells to the
    # terminal and was one cell to us: a 24-cell budget rendered 72 columns.
    lo=128; hi=191
    case "$b0" in
        224) lo=160 ;;   # 0xE0: 0x80-0x9F would be an overlong 2-byte form
        237) hi=159 ;;   # 0xED: 0xA0-0xBF would be a UTF-16 surrogate
        240) lo=144 ;;   # 0xF0: 0x80-0x8F would be an overlong 3-byte form
        244) hi=143 ;;   # 0xF4: 0x90-0xBF would be past U+10FFFF
    esac

    # Each continuation byte must be in range, and must exist. A truncated tail
    # at end-of-string is the other half of the same bug: it used to decode the
    # missing bytes as zeroes and invent a wide CJK glyph out of nothing.
    b1=0; b2=0; b3=0; k=1
    while [ "$k" -le "$need" ]; do
        bc="${s:$((i+k)):1}"
        if [ -z "$bc" ]; then USEFUL_CP=$b0; USEFUL_CP_LEN=1; return; fi
        printf -v bb '%d' "'$bc"
        [ "$bb" -lt 0 ] && bb=$(( bb + 256 ))
        if [ "$bb" -lt "$lo" ] || [ "$bb" -gt "$hi" ]; then
            USEFUL_CP=$b0; USEFUL_CP_LEN=1; return
        fi
        case "$k" in 1) b1=$bb ;; 2) b2=$bb ;; *) b3=$bb ;; esac
        # Only the first continuation byte is constrained further.
        lo=128; hi=191
        k=$(( k + 1 ))
    done

    case "$need" in
        1) USEFUL_CP=$(( ((b0 & 31) << 6) | (b1 & 63) )); USEFUL_CP_LEN=2 ;;
        2) USEFUL_CP=$(( ((b0 & 15) << 12) | ((b1 & 63) << 6) | (b2 & 63) )); USEFUL_CP_LEN=3 ;;
        *) USEFUL_CP=$(( ((b0 & 7) << 18) | ((b1 & 63) << 12) | ((b2 & 63) << 6) | (b3 & 63) ))
           USEFUL_CP_LEN=4 ;;
    esac
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
    elif [ "$cp" -ge 6832 ]   && [ "$cp" -le 6911 ];     then USEFUL_CW=0  # U+1AB0-1AFF combining ext
    elif [ "$cp" -ge 7616 ]   && [ "$cp" -le 7679 ];     then USEFUL_CW=0  # U+1DC0-1DFF combining supp
    elif [ "$cp" -ge 8203 ]   && [ "$cp" -le 8205 ];     then USEFUL_CW=0  # U+200B-200D ZWSP/ZWNJ/ZWJ
    elif [ "$cp" -ge 8400 ]   && [ "$cp" -le 8432 ];     then USEFUL_CW=0  # U+20D0-20F0 marks for symbols
    elif [ "$cp" -ge 65056 ]  && [ "$cp" -le 65071 ];    then USEFUL_CW=0  # U+FE20-FE2F combining half marks
    elif [ "$cp" -ge 65024 ]  && [ "$cp" -le 65039 ];    then USEFUL_CW=0  # U+FE00-FE0F variation selectors
    elif [ "$cp" -ge 4352 ]   && [ "$cp" -le 4447 ];     then USEFUL_CW=2  # U+1100-115F Hangul Jamo
    elif [ "$cp" -ge 11904 ]  && [ "$cp" -le 12350 ];    then USEFUL_CW=2  # U+2E80-303E CJK radicals/symbols
    elif [ "$cp" -ge 12353 ]  && [ "$cp" -le 19967 ];    then USEFUL_CW=2  # U+3041-4DFF kana .. Yijing
    elif [ "$cp" -ge 19968 ]  && [ "$cp" -le 42191 ];    then USEFUL_CW=2  # U+4E00-A4CF CJK unified + Yi
    elif [ "$cp" -ge 43360 ]  && [ "$cp" -le 43391 ];    then USEFUL_CW=2  # U+A960-A97F Hangul Jamo ext-A
    elif [ "$cp" -ge 44032 ]  && [ "$cp" -le 55203 ];    then USEFUL_CW=2  # U+AC00-D7A3 Hangul syllables
    elif [ "$cp" -ge 63744 ]  && [ "$cp" -le 64255 ];    then USEFUL_CW=2  # U+F900-FAFF CJK compat
    elif [ "$cp" -ge 65040 ]  && [ "$cp" -le 65049 ];    then USEFUL_CW=2  # U+FE10-FE19 vertical forms
    elif [ "$cp" -ge 65072 ]  && [ "$cp" -le 65135 ];    then USEFUL_CW=2  # U+FE30-FE6F CJK compat forms
    elif [ "$cp" -ge 65280 ]  && [ "$cp" -le 65376 ];    then USEFUL_CW=2  # U+FF00-FF60 fullwidth
    elif [ "$cp" -ge 65504 ]  && [ "$cp" -le 65510 ];    then USEFUL_CW=2  # U+FFE0-FFE6 fullwidth signs
    elif [ "$cp" -ge 127744 ] && [ "$cp" -le 983039 ];   then USEFUL_CW=2  # U+1F300-EFFFF emoji + astral CJK
    # Wide glyphs in the astral planes that sit BELOW U+1F300. Listed one range
    # at a time rather than lowering the floor to U+1F000: the mahjong, playing
    # card and enclosed-alphanumeric blocks in between are mostly narrow, and
    # widening them wholesale would truncate strings that fit. Over-counting is
    # the safe direction, but it is still wrong.
    elif [ "$cp" -eq 126980 ] || [ "$cp" -eq 127183 ];   then USEFUL_CW=2  # U+1F004 mahjong, U+1F0CF joker
    elif [ "$cp" -eq 127374 ];                           then USEFUL_CW=2  # U+1F18E AB button
    elif [ "$cp" -ge 127377 ] && [ "$cp" -le 127386 ];   then USEFUL_CW=2  # U+1F191-1F19A CL..VS buttons
    elif [ "$cp" -ge 127488 ] && [ "$cp" -le 127490 ];   then USEFUL_CW=2  # U+1F200-1F202 squared kana
    elif [ "$cp" -ge 127504 ] && [ "$cp" -le 127547 ];   then USEFUL_CW=2  # U+1F210-1F23B squared CJK
    elif [ "$cp" -ge 127552 ] && [ "$cp" -le 127560 ];   then USEFUL_CW=2  # U+1F240-1F248 tortoise-shell CJK
    elif [ "$cp" -ge 127568 ] && [ "$cp" -le 127569 ];   then USEFUL_CW=2  # U+1F250-1F251 circled CJK
    # Wide glyphs that live BELOW the astral emoji block. These are
    # Emoji_Presentation=Yes / East_Asian_Width=Wide, so a terminal draws them
    # in two cells with no U+FE0F to ask for it — and the FE0F promotion above
    # is what used to be doing all the work here. Undercounting is the unsafe
    # direction: it overflows the very budget useful_truncate exists to
    # guarantee. wttr.in's %c — this project's DEFAULT @useful-weather-format —
    # emits bare U+26C5 and U+26C8, so an 8-cell budget rendered 13 columns.
    elif [ "$cp" -ge 8986 ]   && [ "$cp" -le 8987 ];     then USEFUL_CW=2  # U+231A-231B watch, hourglass
    elif [ "$cp" -ge 9193 ]   && [ "$cp" -le 9196 ];     then USEFUL_CW=2  # U+23E9-23EC fast-forward
    elif [ "$cp" -eq 9200 ] || [ "$cp" -eq 9203 ];       then USEFUL_CW=2  # U+23F0 alarm, U+23F3 hourglass
    elif [ "$cp" -ge 9725 ]   && [ "$cp" -le 9726 ];     then USEFUL_CW=2  # U+25FD-25FE medium squares
    elif [ "$cp" -ge 9748 ]   && [ "$cp" -le 9749 ];     then USEFUL_CW=2  # U+2614-2615 umbrella, coffee
    elif [ "$cp" -ge 9800 ]   && [ "$cp" -le 9811 ];     then USEFUL_CW=2  # U+2648-2653 zodiac
    elif [ "$cp" -eq 9855 ] || [ "$cp" -eq 9875 ];       then USEFUL_CW=2  # U+267F wheelchair, U+2693 anchor
    elif [ "$cp" -eq 9889 ];                             then USEFUL_CW=2  # U+26A1 high voltage
    elif [ "$cp" -ge 9898 ]   && [ "$cp" -le 9899 ];     then USEFUL_CW=2  # U+26AA-26AB circles
    elif [ "$cp" -ge 9917 ]   && [ "$cp" -le 9918 ];     then USEFUL_CW=2  # U+26BD-26BE soccer, baseball
    elif [ "$cp" -ge 9924 ]   && [ "$cp" -le 9925 ];     then USEFUL_CW=2  # U+26C4-26C5 snowman, sun-behind-cloud
    elif [ "$cp" -eq 9928 ] || [ "$cp" -eq 9934 ];       then USEFUL_CW=2  # U+26C8 thunder cloud, U+26CE Ophiuchus
    elif [ "$cp" -eq 9940 ] || [ "$cp" -eq 9962 ];       then USEFUL_CW=2  # U+26D4 no entry, U+26EA church
    elif [ "$cp" -ge 9970 ]   && [ "$cp" -le 9971 ];     then USEFUL_CW=2  # U+26F2-26F3 fountain, golf
    elif [ "$cp" -eq 9973 ] || [ "$cp" -eq 9978 ];       then USEFUL_CW=2  # U+26F5 sailboat, U+26FA tent
    elif [ "$cp" -eq 9981 ] || [ "$cp" -eq 9989 ];       then USEFUL_CW=2  # U+26FD fuel, U+2705 check mark
    elif [ "$cp" -ge 9994 ]   && [ "$cp" -le 9995 ];     then USEFUL_CW=2  # U+270A-270B raised fist/hand
    elif [ "$cp" -eq 10024 ] || [ "$cp" -eq 10060 ];     then USEFUL_CW=2  # U+2728 sparkles, U+274C cross mark
    elif [ "$cp" -eq 10062 ];                            then USEFUL_CW=2  # U+274E cross mark button
    elif [ "$cp" -ge 10067 ]  && [ "$cp" -le 10069 ];    then USEFUL_CW=2  # U+2753-2755 question marks
    elif [ "$cp" -eq 10071 ];                            then USEFUL_CW=2  # U+2757 exclamation mark
    elif [ "$cp" -ge 10133 ]  && [ "$cp" -le 10135 ];    then USEFUL_CW=2  # U+2795-2797 plus, minus, divide
    elif [ "$cp" -eq 10160 ] || [ "$cp" -eq 10175 ];     then USEFUL_CW=2  # U+27B0 curly loop, U+27BF double loop
    elif [ "$cp" -ge 11035 ]  && [ "$cp" -le 11036 ];    then USEFUL_CW=2  # U+2B1B-2B1C large squares
    elif [ "$cp" -eq 11088 ] || [ "$cp" -eq 11093 ];     then USEFUL_CW=2  # U+2B50 star, U+2B55 hollow circle
    elif [ "$cp" -ge 9001 ]   && [ "$cp" -le 9002 ];     then USEFUL_CW=2  # U+2329-232A angle brackets
    elif [ "$cp" -ge 9776 ]   && [ "$cp" -le 9783 ];     then USEFUL_CW=2  # U+2630-2637 trigrams
    elif [ "$cp" -ge 9866 ]   && [ "$cp" -le 9871 ];     then USEFUL_CW=2  # U+268A-268F mono/digrams
    elif [ "$cp" -ge 94176 ]  && [ "$cp" -le 101640 ];   then USEFUL_CW=2  # U+16FE0-18D08 Tangut/Khitan/Nushu
    elif [ "$cp" -ge 110576 ] && [ "$cp" -le 111355 ];   then USEFUL_CW=2  # U+1AFF0-1B2FB kana extensions
    elif [ "$cp" -ge 119552 ] && [ "$cp" -le 119670 ];   then USEFUL_CW=2  # U+1D300-1D376 Tai Xuan Jing
    elif [ "$cp" -ge 127584 ] && [ "$cp" -le 127589 ];   then USEFUL_CW=2  # U+1F260-1F265 rounded symbols
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

# Longest run of zero-width marks allowed to ride on one base glyph.
#
# Only U+0300-036F, ZWJ and the variation selectors measure zero here, and no
# real script stacks more than three of those. Without a cap, a cell budget is
# not a bound on anything: 500 combining acutes measure ONE cell, so the whole
# run is "in budget" and 501 characters reach a terminal that was promised 5.
# That is the zalgo overflow, and a Spotify track title is enough to trigger it.
USEFUL_MAX_MARKS=4

# Hard ceiling on any cell budget, whatever a @useful-*-max-len says.
#
# No terminal is 20,000 columns wide, so a budget that large is not a budget —
# it is the absence of one. It matters because bash's ${var//pat/rep} is
# quadratic in the NUMBER OF MATCHES (measured: 2k matches 0.6s, 4k 4.3s, 8k
# 38s), and useful_escape doubles every '#'. A hash-dense wttr.in body — the
# captive-portal splash these caps exist for — therefore turned a raised
# max-len into minutes of CPU with the status line frozen behind it. Capping
# the budget is what keeps that input bounded before it ever reaches escaping.
USEFUL_MAX_CELLS=512

# Extract the run of $1 beginning at cell offset $2 and spanning at most $3
# cells. Sets USEFUL_WINDOW, plus USEFUL_WINDOW_CUT_HEAD / _CUT_TAIL to 1 when
# content was dropped before / after the window. Never splits a character.
#
# USEFUL_WINDOW_CUT_TAIL means one specific thing: RENDERABLE content was left
# behind because the cell budget ran out. It is what useful_truncate uses to
# decide whether an ellipsis is owed, so the mark clamp must NOT set it —
# clamping is a defensive trim of glyphs that occupy no cells, and a string
# whose visible content fits perfectly is not truncated just because one of its
# characters carried five accents. That conflation put a spurious "…" on
# in-budget branch names and, at an exact fit, dropped a real character to make
# room for it. USEFUL_WINDOW_MARKS_CLAMPED reports the clamp separately.
# shellcheck disable=SC2034  # CUT_HEAD/CUT_TAIL consumed by spotify.sh and
# useful_truncate; MARKS_CLAMPED/SCAN_LIMITED are diagnostics no caller reads yet
useful_window() {
    local LC_ALL=C
    local s="$1" start="$2" max="$3"
    local n i=0 acc=0 taken=0 out="" chunk prev=0 cw zrun=0 scanned=0 scan_limit
    USEFUL_WINDOW=""; USEFUL_WINDOW_CUT_HEAD=0; USEFUL_WINDOW_CUT_TAIL=0
    USEFUL_WINDOW_MARKS_CLAMPED=0; USEFUL_WINDOW_SCAN_LIMITED=0
    n=${#s}
    [ "$max" -lt 1 ] && return
    # Capping the budget is not itself a cut. If the content really does exceed
    # the capped budget the loop below will say so; if it does not, a budget the
    # caller inflated to 20,000 must not conjure an ellipsis onto a short string.
    [ "$max" -gt "$USEFUL_MAX_CELLS" ] && max=$USEFUL_MAX_CELLS

    # Ceiling on codepoints VISITED, not just on cells kept.
    #
    # `taken` is the budget counter, and zero-width marks never advance it — so
    # a string that is *only* marks keeps `taken` at 0 forever and the loop
    # walks the whole input however small the budget was. That is the same hole
    # the mark clamp closed for OUTPUT length, still open for SCAN cost: a
    # 5,000-mark Spotify title froze the driver for seconds on stock defaults,
    # in pure bash, where neither @useful-timeout nor @useful-timeout-total can
    # reach it.
    #
    # The bound is exact rather than arbitrary: reaching cell `start + max`
    # takes at most that many base glyphs, and each may keep USEFUL_MAX_MARKS
    # marks. Anything past that is necessarily a mark this function would have
    # dropped anyway, so stopping costs no content a correct run would have kept.
    scan_limit=$(( (start + max) * (USEFUL_MAX_MARKS + 1) + 16 ))

    # And cut the input itself, not only the iteration count. Bash slices a
    # string in time proportional to its LENGTH, so `${s:$i:$len}` stays
    # expensive on a 40KB input even when the loop around it is bounded.
    # LC_ALL=C is in force here, so the slice is bytewise, as intended.
    #
    # This trades fidelity for a bound, and the trade is real: content sitting
    # AFTER an oversized mark run is past the cut and is lost, even though a
    # renderer with unlimited time would have shown it — "a" + 100k marks +
    # "bbb" yields "a" plus four marks, without the "bbb". That is a deliberate
    # choice, not an oversight. Skipping a mark run cheaply is not something
    # bash 3.2 can do, and no real text carries thousands of stacked marks, so
    # the alternative is a status line that a hostile track title can freeze.
    # USEFUL_WINDOW_SCAN_LIMITED reports it, separately from CUT_TAIL, because
    # "we stopped looking" and "the tail did not fit" are different claims.
    local max_bytes=$(( scan_limit * 4 )) precut=0
    if [ "$n" -gt "$max_bytes" ]; then
        s="${s:0:$max_bytes}"
        n=$max_bytes
        precut=1
        USEFUL_WINDOW_CUT_TAIL=1
    fi

    while [ "$i" -lt "$n" ]; do
        scanned=$(( scanned + 1 ))
        if [ "$scanned" -gt "$scan_limit" ]; then
            USEFUL_WINDOW_CUT_TAIL=1; USEFUL_WINDOW_SCAN_LIMITED=1; break
        fi
        useful_utf8_decode "$s" "$i"
        chunk="${s:$i:$USEFUL_CP_LEN}"
        i=$(( i + USEFUL_CP_LEN ))
        useful_cp_width "$USEFUL_CP"
        cw=$USEFUL_CW
        if [ "$USEFUL_CP" -eq 65039 ] && [ "$prev" -eq 1 ]; then
            cw=1   # the selector itself is zero-width; it adds a cell to the previous glyph
        fi
        prev=$USEFUL_CW
        # Zero-width marks never advance `taken`, so the budget test below can
        # never stop them. Count the run and drop the overflow instead.
        if [ "$cw" -eq 0 ]; then
            zrun=$(( zrun + 1 ))
            if [ "$zrun" -gt "$USEFUL_MAX_MARKS" ]; then
                # Dropped, but not a truncation: these occupy no cells, so the
                # budget is untouched and no ellipsis is owed. The scan ceiling
                # above is what bounds the cost of a long run; breaking out here
                # on a full budget would be wrong, because the run may still be
                # followed by content that fits exactly.
                USEFUL_WINDOW_MARKS_CLAMPED=1
                continue
            fi
        else
            zrun=0
        fi
        if [ "$acc" -lt "$start" ]; then
            acc=$(( acc + cw )); USEFUL_WINDOW_CUT_HEAD=1; continue
        fi
        if [ $(( taken + cw )) -gt "$max" ]; then USEFUL_WINDOW_CUT_TAIL=1; break; fi
        out="$out$chunk"
        taken=$(( taken + cw ))
    done
    # SCAN_LIMITED means "we stopped examining input before the budget was
    # satisfied", which the pre-cut alone does not establish: an ordinary long
    # string gets cut too, and if the loop then filled the budget, nothing was
    # given up that the budget would not have stopped anyway. Only a cut that
    # left us short of the budget actually cost us reachable content.
    if [ "$precut" -eq 1 ] && [ "$taken" -lt "$max" ]; then
        USEFUL_WINDOW_SCAN_LIMITED=1
    fi
    USEFUL_WINDOW="$out"
}

# Sets USEFUL_TRUNC to $1 fitted into $2 cells, appending $3 (default "…")
# when it had to cut. The ellipsis is charged against the budget.
# shellcheck disable=SC2034  # USEFUL_TRUNC is read by callers (git.sh, pane.sh)
useful_truncate() {
    local s="$1" max="$2" ell="${3-…}" ew
    [ "$max" -gt "$USEFUL_MAX_CELLS" ] && max=$USEFUL_MAX_CELLS
    # Ask the window first, and read its verdict, instead of measuring the whole
    # string to decide whether it fits. useful_window stops as soon as the
    # budget is spent, so this costs O(budget); measuring costs O(length), and
    # decoding 20,000 characters to learn that they do not fit in 24 cells is
    # work with no answer in it. Routing through the window also applies the
    # mark clamp — a string that MEASURES one cell can still be an unbounded run
    # of combining marks, and "fits the budget" is not "bounded in length".
    useful_window "$s" 0 "$max"
    if [ "$USEFUL_WINDOW_CUT_TAIL" -eq 0 ]; then
        USEFUL_TRUNC="$USEFUL_WINDOW"
        return
    fi
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
        # Each position is a hex digit, not any character. `fg=#??????` also
        # matched "#gggggg" — a plausible typo in @useful-color-* — and then
        # $((16#gg)) failed the assignment with "value too great for base" on
        # a stderr the user may well be watching.
        fg=#[0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F][0-9a-fA-F])
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

# Escape text that did NOT come from this repo before it joins the markup.
#
# A git branch, a Spotify track title and a wttr.in response are all authored
# elsewhere, and all three land in a tmux format string. Any '#' in them is
# live syntax: "#[bg=red]" repaints the bar (a background block, which
# AGENTS.md bans outright), and "#{...}" expands as a format. "##" is tmux's
# escape for a literal '#', and useful_render below turns it back into one for
# the non-tmux hosts.
#
# Deliberately NOT applied to @useful-* option values. Those are the user's own
# tmux config — already trusted, already able to set any tmux option directly,
# and escaping them would break anyone deliberately colouring an icon.
useful_escape() {
    local s="$1"
    # Control characters first. A status line is one line by contract, and a
    # wttr.in body — a captive-portal splash, an error page — can carry raw
    # newlines that break it. Worse, a lone CR returns the cursor and lets
    # attacker-controlled text overprint the segment's own output, hiding the
    # "~" stale marker or forging a truncation ellipsis. They also produce
    # JSON that RFC 8259 forbids, so a strict waybar-side parser rejects the
    # whole object. Replaced with a space rather than deleted, so words on
    # either side do not fuse; a space is also what our width table already
    # charges for a control byte, which keeps the cell budget honest.
    s="${s//[[:cntrl:]]/ }"
    printf "%s" "${s//#/##}"
}

# useful_render <tmux|ansi|plain> <text>
useful_render() {
    local mode="$1" text="$2" out="" pre rest tok
    [ "$mode" = "tmux" ] && { printf "%s" "$text"; return; }
    # Collapse the "##" escape in ONE bulk substitution before scanning.
    #
    # This is a performance fix, not a cosmetic one. The scan below consumes the
    # text up to the next '#' and re-slices the remainder each time, so its cost
    # is quadratic in the number of '#' it has to visit — and escaped text is
    # ALL hashes. A 20k-hash wttr.in body (a captive-portal splash, the exact
    # scenario the length cap was added for) took over a minute; the same input
    # after this pass leaves nothing for the loop to visit at all, because every
    # hash in untrusted text is doubled by useful_escape and collapses here.
    # What remains is this repo's own markup: about a dozen tokens.
    #
    # U+0001 is safe as the placeholder precisely because useful_escape strips
    # control characters, so it cannot occur in escaped text. If it shows up
    # anyway — a direct caller passing raw bytes — skip the shortcut and let the
    # scan handle "##" itself, which it still does, just slowly.
    local ph=$'\001' unescape=0
    case "$text" in
        *"$ph"*) ;;
        *'##'*)  text="${text//\#\#/$ph}"; unescape=1 ;;
    esac
    # Scans '#' rather than '#[' so that the "##" escape is decoded here too.
    # Matching '#[' alone would read the second '#' of an escaped "###[fg=red]"
    # as the start of a real attribute and let escaped text style the output of
    # the very modes that are supposed to be inert.
    while [ -n "$text" ]; do
        case "$text" in
            *'#'*)
                pre="${text%%#*}"
                out="$out$pre"
                rest="${text#*#}"
                case "$rest" in
                    '#'*)        out="$out#"; text="${rest#?}" ;;
                    '['*']'*)    tok="${rest#\[}"; tok="${tok%%\]*}"
                                 text="${rest#*\]}"
                                 if [ "$mode" = "ansi" ]; then
                                     useful_ansi_attr "$tok"
                                     out="$out$ANSI"
                                 fi
                                 ;;
                    # A lone '#', or a '#[' that never closes. Emit it as text;
                    # `rest` is strictly shorter each pass, so this terminates.
                    *)           out="$out#"; text="$rest" ;;
                esac
                ;;
            *) out="$out$text"; text="" ;;
        esac
    done
    [ "$unescape" -eq 1 ] && out="${out//$ph/#}"
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
    s="${s//$'\r'/\\r}"
    # Belt and braces behind useful_escape: any other C0 control that reaches
    # here would be a literal control byte inside a JSON string, which RFC 8259
    # forbids outright. A consumer that parses strictly rejects the whole
    # object, so the segment that misbehaved takes the other five down with it.
    s="${s//[[:cntrl:]]/ }"
    printf "%s" "$s"
}

# Marks helpers as present in THIS shell. Deliberately not exported: a segment
# run as a subprocess must still source helpers itself. Sourcing this file
# again always re-runs everything above, which is how tests re-evaluate a
# changed @useful-theme.
# shellcheck disable=SC2034  # read by the guard at the top of each segment
USEFUL_HELPERS_LOADED=1
