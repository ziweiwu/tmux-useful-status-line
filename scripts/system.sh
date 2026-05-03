#!/usr/bin/env bash
# CPU load / memory / disk health for tmux status bar.
# Silent when healthy, warns above threshold.
# macOS only.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$DIR/helpers.sh"

segment_enabled "system" || exit 0

# OS-specific data sources. macOS uses sysctl/memory_pressure/df; Linux uses
# /proc and `free`. Tests inject paths via TMUX_USEFUL_PROC / PATH stubs.
PROC_DIR="${TMUX_USEFUL_PROC:-/proc}"

if is_darwin; then
    :
elif is_linux; then
    :
else
    exit 0
fi

CACHE_FILE="$(useful_cache_dir)/system"
cache_check "$CACHE_FILE" 5 && exit 0

WARN=$(color_warn)
CRIT=$(color_crit)
DIM=$(color_dim)

LOAD_WARN=$(get_tmux_option "@useful-load-warn" 70)
LOAD_CRIT=$(get_tmux_option "@useful-load-crit" 100)
MEM_WARN=$(get_tmux_option "@useful-mem-warn" 75)
MEM_CRIT=$(get_tmux_option "@useful-mem-crit" 90)
DISK_WARN=$(get_tmux_option "@useful-disk-warn" 80)
DISK_CRIT=$(get_tmux_option "@useful-disk-crit" 95)

# Defaults are short text labels — clearer than glyphs at a glance, and they
# render in any terminal without a Nerd Font. Override to glyphs if you
# prefer:  set -g @useful-icon-load "" / @useful-icon-mem "" / @useful-icon-disk "󰋊"
ICON_LOAD=$(get_tmux_option "@useful-icon-load" "cpu")
ICON_MEM=$(get_tmux_option "@useful-icon-mem" "mem")
ICON_DISK=$(get_tmux_option "@useful-icon-disk" "disk")

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
    load1=$(sysctl -n vm.loadavg | awk '{print $2}')
    ncpu=$(sysctl -n hw.ncpu)
else
    load1=$(cut -d' ' -f1 "$PROC_DIR/loadavg" 2>/dev/null)
    ncpu=$(nproc 2>/dev/null || grep -c '^processor' "$PROC_DIR/cpuinfo" 2>/dev/null || echo 1)
fi
load_pct=$(awk -v l="${load1:-0}" -v n="${ncpu:-1}" 'BEGIN { printf "%d", (l/n)*100 }')
# Crit warnings get a leading "!" so users with deuteranopia/protanopia can
# distinguish warn (yellow→mustard) from crit (red→mustard) without color.
# Healthy values render in dim when an "always" mode is selected.
# Render the CPU value either as text "cpu 70%" or as a fill-bar where each
# character represents one core's worth of load. With load1=7 on ncpu=10,
# bar = "███████░░░" — visually shows utilization across cores.
CPU_STYLE=$(get_tmux_option "@useful-cpu-style" "text")
cpu_value=""
if [ "$CPU_STYLE" = "bar" ]; then
    bar_width="${ncpu:-1}"
    [ "$bar_width" -gt 16 ] && bar_width=16
    [ "$bar_width" -lt 4 ] && bar_width=4
    # Glyphs: empty + 1/8 .. 8/8 fill steps for sub-character precision.
    glyphs="░▏▎▍▌▋▊▉█"
    load_eighths=$(awk -v l="${load1:-0}" 'BEGIN { printf "%d", l * 8 }')
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
LOAD_CRIT_PREFIX=$(get_tmux_option "@useful-load-crit-prefix" "!")
MEM_CRIT_PREFIX=$(get_tmux_option "@useful-mem-crit-prefix" "!")
DISK_CRIT_PREFIX=$(get_tmux_option "@useful-disk-crit-prefix" "!")
case "$LOAD_CRIT_PREFIX" in none|off|false|0|no) LOAD_CRIT_PREFIX="" ;; esac
case "$MEM_CRIT_PREFIX"  in none|off|false|0|no) MEM_CRIT_PREFIX=""  ;; esac
case "$DISK_CRIT_PREFIX" in none|off|false|0|no) DISK_CRIT_PREFIX="" ;; esac

if [ "$load_pct" -ge "$LOAD_CRIT" ]; then
    out+=" #[fg=$CRIT]${LOAD_CRIT_PREFIX}$ICON_LOAD $cpu_value"
elif [ "$load_pct" -ge "$LOAD_WARN" ]; then
    out+=" #[fg=$WARN]$ICON_LOAD $cpu_value"
elif should_show_healthy load; then
    out+=" #[fg=$DIM]$ICON_LOAD $cpu_value"
fi

if is_darwin; then
    mem_free=$(memory_pressure | awk '/System-wide memory free percentage/ {gsub("%",""); print $5}')
    mem=$(( 100 - ${mem_free:-0} ))
else
    # Linux: prefer the available column when present (free since procps 3.3.10).
    mem=$(free 2>/dev/null | awk '/^Mem:/ {
        if (NF >= 7) printf "%d", ($2 - $7)/$2 * 100;
        else         printf "%d", $3/$2 * 100;
    }')
    mem="${mem:-0}"
fi
if [ "$mem" -ge "$MEM_CRIT" ]; then
    out+=" #[fg=$CRIT]${MEM_CRIT_PREFIX}$ICON_MEM ${mem}%"
elif [ "$mem" -ge "$MEM_WARN" ]; then
    out+=" #[fg=$WARN]$ICON_MEM ${mem}%"
elif should_show_healthy mem; then
    out+=" #[fg=$DIM]$ICON_MEM ${mem}%"
fi

disk=$(df -h / | awk 'NR==2 {gsub("%",""); print $5}')
if [ "$disk" -ge "$DISK_CRIT" ]; then
    out+=" #[fg=$CRIT]${DISK_CRIT_PREFIX}$ICON_DISK ${disk}%"
elif [ "$disk" -ge "$DISK_WARN" ]; then
    out+=" #[fg=$WARN]$ICON_DISK ${disk}%"
elif should_show_healthy disk; then
    out+=" #[fg=$DIM]$ICON_DISK ${disk}%"
fi

[ -n "$out" ] && out+="#[fg=default]"

printf "%s" "$out" | tee "$CACHE_FILE"
