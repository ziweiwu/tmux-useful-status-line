#!/usr/bin/env bash
# CPU load / memory / disk health for tmux status bar.
# Silent when healthy, warns above threshold.
# macOS only.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Guarded so bin/useful-status can source helpers once and then source all
# six segments without each re-running the config snapshot.
# shellcheck source=helpers.sh
[ -n "${USEFUL_HELPERS_LOADED:-}" ] || source "$DIR/helpers.sh"

# The body lives in a function so the six segments can share one process.
# Deliberately not re-indented: it keeps this diff reviewable and leaves
# column-0 heredoc terminators intact.
useful_segment_system() {
segment_enabled "system" || return 0

# OS-specific data sources. macOS uses sysctl/memory_pressure/df; Linux uses
# /proc and `free`. Tests inject paths via TMUX_USEFUL_PROC / PATH stubs.
PROC_DIR="${TMUX_USEFUL_PROC:-/proc}"

if is_darwin; then
    :
elif is_linux; then
    :
else
    return 0
fi

CACHE_FILE="$(useful_cache_dir)/system"
cache_check "$CACHE_FILE" 5 && return 0

WARN=$(color_warn)
CRIT=$(color_crit)
DIM=$(color_dim)

LOAD_WARN=$(useful_int_option "@useful-load-warn" 70)
LOAD_CRIT=$(useful_int_option "@useful-load-crit" 100)
MEM_WARN=$(useful_int_option "@useful-mem-warn" 75)
MEM_CRIT=$(useful_int_option "@useful-mem-crit" 90)
DISK_WARN=$(useful_int_option "@useful-disk-warn" 80)
DISK_CRIT=$(useful_int_option "@useful-disk-crit" 95)
# Wall-clock budget for each data source. `df` on a stale NFS mount and
# `sysctl` during an IOKit stall both block forever; the driver runs the six
# segments serially, so one of them takes the whole status line down with it.
TIMEOUT=$(useful_int_option "@useful-timeout" 3)

# Defaults are short text labels — clearer than glyphs at a glance, and they
# render in any terminal without a Nerd Font. Override to glyphs if you
# prefer:  set -g @useful-icon-load "" / @useful-icon-mem "" / @useful-icon-disk "󰋊"
ICON_LOAD=$(useful_icon_option "@useful-icon-load" "cpu")
ICON_MEM=$(useful_icon_option "@useful-icon-mem" "mem")
ICON_DISK=$(useful_icon_option "@useful-icon-disk" "disk")

# Visibility mode for healthy values:
#   warn-and-crit       — silent when healthy (default; original "state-only" design)
#   mem-and-disk-always — show mem and disk even when healthy; load only on warn/crit
#   all-always          — show all three always
SHOW_WHEN=$(get_tmux_option "@useful-system-show-when" "warn-and-crit")

# Returns 0 if a metric should also render in its healthy band.
should_show_healthy() {
    case "$SHOW_WHEN" in
        all-always) return 0 ;;
        mem-and-disk-always)
            case "$1" in mem|disk) return 0 ;; *) return 1 ;; esac ;;
        *) return 1 ;;
    esac
}

out=""

if is_darwin; then
    load1=$(useful_timeout "$TIMEOUT" sysctl -n vm.loadavg 2>/dev/null | awk '{print $2}')
    ncpu=$(useful_timeout "$TIMEOUT" sysctl -n hw.ncpu 2>/dev/null)
else
    load1=$(cut -d' ' -f1 "$PROC_DIR/loadavg" 2>/dev/null)
    ncpu=$(useful_timeout "$TIMEOUT" nproc 2>/dev/null || grep -c '^processor' "$PROC_DIR/cpuinfo" 2>/dev/null || echo 1)
fi
# Data sources lie. A container with a clamped /proc, a localized sysctl, a
# truncated read — any of them can hand back a non-number, and `[ x -ge y ]`
# would then print "integer expression expected" to a stderr tmux discards and
# blank the segment. Coerce here instead. awk is doing the float work, so only
# the values that reach a shell `[` test need to be integers.
case "$ncpu" in ''|*[!0-9]*|??????????*) ncpu=1 ;; esac
[ "$ncpu" -eq 0 ] && ncpu=1
load_pct=$(awk -v l="${load1:-0}" -v n="$ncpu" 'BEGIN { printf "%d", (l/n)*100 }')
case "$load_pct" in ''|*[!0-9]*|??????????*) load_pct=0 ;; esac
# Crit warnings get a leading "!" so users with deuteranopia/protanopia can
# distinguish warn (yellow→mustard) from crit (red→mustard) without color.
# Healthy values render in dim when an "always" mode is selected.
# Render the CPU value either as text "cpu 70%" or as a fill-bar where each
# character represents one core's worth of load. With load1=7 on ncpu=10,
# bar = "███████░░░" — visually shows utilization across cores.
CPU_STYLE=$(get_tmux_option "@useful-cpu-style" "text")
cpu_value=""
if [ "$CPU_STYLE" = "bar" ]; then
    bar_width="$ncpu"
    [ "$bar_width" -gt 16 ] && bar_width=16
    [ "$bar_width" -lt 4 ] && bar_width=4
    # Glyphs: empty + 1/8 .. 8/8 fill steps for sub-character precision.
    glyphs="░▏▎▍▌▋▊▉█"
    load_eighths=$(awk -v l="${load1:-0}" 'BEGIN { printf "%d", l * 8 }')
    # A negative load (a corrupt /proc/loadavg, a sysctl that returned "-1")
    # must not reach ${glyphs:$remaining:1}: with remaining="-5" that expands
    # as ${glyphs:-5:1}, the *default-value* operator, and splices the entire
    # glyph string into the bar instead of one character.
    case "$load_eighths" in ''|*[!0-9]*|??????????*) load_eighths=0 ;; esac
    max_eighths=$(( bar_width * 8 ))
    [ "$load_eighths" -gt "$max_eighths" ] && load_eighths="$max_eighths"
    bar=""
    remaining="$load_eighths"
    for ((i=0; i<bar_width; i++)); do
        if [ "$remaining" -ge 8 ]; then
            bar+="█"
            remaining=$(( remaining - 8 ))
        else
            bar+="${glyphs:$remaining:1}"
            remaining=0
        fi
    done
    cpu_value="$bar"
else
    cpu_value="${load_pct}%"
fi

# Per-metric crit prefix (default "!" for color-blind clarity). Set to
# "none" / "off" / "false" to suppress when color alone is enough.
# Warn shares the crit prefix's purpose: a cue that does not depend on colour.
# It defaults to empty because in the default "silent when healthy" mode the
# segment appearing at all IS the cue. Under @useful-system-show-when
# all-always / mem-and-disk-always, healthy values are rendered too, so colour
# becomes the only thing separating warn from healthy — set this there.
# Crit is "!" everywhere, always. Warn gets its own glyph where it needs one.
#
# In warn-and-crit (the default) a healthy metric renders nothing at all, so the
# segment APPEARING is already the colour-free cue and warn needs no prefix.
# Under an "always" mode healthy values render too, and dim-vs-warn collapses to
# a difference of hue alone — invisible with deuteranopia or protanopia, and
# gone entirely under --render=plain. So warn takes "~" there.
#
# "~" rather than a second "!": prefix COUNT reads as severity everywhere else
# in a terminal — git hooks, npm audit, log levels — so letting crit vary
# between segments would state something false to the one audience that has
# nothing but the prefix to read. A status line is read as one line, not six
# independent segments, and `!mem 95%` beside `!!batt 15%` says the battery is
# worse when both are critical. Distinguishing SHAPE also beats distinguishing
# count at a glance, which is the actual way a status bar gets read. "~" is
# already this project's "advisory, not alarm" marker on stale weather data, so
# it adds no new vocabulary.
case "$SHOW_WHEN" in
    all-always|mem-and-disk-always) warn_default="~" ;;
    *)                              warn_default=""  ;;
esac

WARN_PREFIX=$(get_tmux_option "@useful-warn-prefix" "$warn_default")
case "$WARN_PREFIX" in none|off|false|0|no) WARN_PREFIX="" ;; esac

LOAD_CRIT_PREFIX=$(get_tmux_option "@useful-load-crit-prefix" "!")
MEM_CRIT_PREFIX=$(get_tmux_option "@useful-mem-crit-prefix" "!")
DISK_CRIT_PREFIX=$(get_tmux_option "@useful-disk-crit-prefix" "!")
case "$LOAD_CRIT_PREFIX" in none|off|false|0|no) LOAD_CRIT_PREFIX="" ;; esac
case "$MEM_CRIT_PREFIX"  in none|off|false|0|no) MEM_CRIT_PREFIX=""  ;; esac
case "$DISK_CRIT_PREFIX" in none|off|false|0|no) DISK_CRIT_PREFIX="" ;; esac

if [ "$load_pct" -ge "$LOAD_CRIT" ]; then
    out+=" #[fg=$CRIT]${LOAD_CRIT_PREFIX}${ICON_LOAD}$cpu_value"
elif [ "$load_pct" -ge "$LOAD_WARN" ]; then
    out+=" #[fg=$WARN]${WARN_PREFIX}${ICON_LOAD}$cpu_value"
elif should_show_healthy load; then
    out+=" #[fg=$DIM]${ICON_LOAD}$cpu_value"
fi

# Memory is the one metric derived by INVERSION (free -> used), so an
# unreadable source is not safe to coerce to 0 the way load and disk are:
# "no answer" would become "100% used" and fire a false critical every
# refresh. An unparseable reading suppresses the metric instead.
mem=""
if is_darwin; then
    # `print $5`, not `printf "%d", $5`: awk coerces a non-number to 0, which
    # would sail through the integer check below and invert into a 100%-used
    # critical. The raw field is what lets the shell tell garbage from data.
    mem_free=$(useful_timeout "$TIMEOUT" memory_pressure 2>/dev/null | awk '/System-wide memory free percentage/ {gsub("%",""); print $5}')
    case "$mem_free" in
        ''|*[!0-9]*|??????????*) ;;
        *) [ "$mem_free" -le 100 ] && mem=$(( 100 - mem_free )) ;;
    esac
else
    # Linux: prefer the available column when present (free since procps 3.3.10).
    mem=$(useful_timeout "$TIMEOUT" free 2>/dev/null | awk '/^Mem:/ {
        if ($2 + 0 <= 0) exit;
        if (NF >= 7) printf "%d", ($2 - $7)/$2 * 100;
        else         printf "%d", $3/$2 * 100;
    }')
    case "$mem" in ''|*[!0-9]*|??????????*) mem="" ;; esac
fi
if [ -n "$mem" ]; then
    if [ "$mem" -ge "$MEM_CRIT" ]; then
        out+=" #[fg=$CRIT]${MEM_CRIT_PREFIX}${ICON_MEM}${mem}%"
    elif [ "$mem" -ge "$MEM_WARN" ]; then
        out+=" #[fg=$WARN]${WARN_PREFIX}${ICON_MEM}${mem}%"
    elif should_show_healthy mem; then
        out+=" #[fg=$DIM]${ICON_MEM}${mem}%"
    fi
fi

# On macOS, df's Capacity column for / describes the sealed read-only APFS
# system snapshot — 12Gi of a 926Gi disk reads as 2%, and never moves, so a
# disk warning could never fire. Total minus available is the real figure.
# Linux's Use% is meaningful (it excludes root-reserved blocks), so it stays.
if is_darwin; then
    disk=$(useful_timeout "$TIMEOUT" df -k / 2>/dev/null | awk 'NR==2 { if ($2 > 0) printf "%d", ($2 - $4) / $2 * 100; else printf "0" }')
else
    disk=$(useful_timeout "$TIMEOUT" df -h / 2>/dev/null | awk 'NR==2 {gsub("%",""); print $5}')
fi
case "$disk" in ''|*[!0-9]*|??????????*) disk=0 ;; esac
if [ "$disk" -ge "$DISK_CRIT" ]; then
    out+=" #[fg=$CRIT]${DISK_CRIT_PREFIX}${ICON_DISK}${disk}%"
elif [ "$disk" -ge "$DISK_WARN" ]; then
    out+=" #[fg=$WARN]${WARN_PREFIX}${ICON_DISK}${disk}%"
elif should_show_healthy disk; then
    out+=" #[fg=$DIM]${ICON_DISK}${disk}%"
fi

[ -n "$out" ] && out+="#[fg=default]"

printf "%s" "$out" | tee "$CACHE_FILE"
}

# tmux calls this script directly via #(...); the driver sources it instead.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    useful_segment_system
fi
