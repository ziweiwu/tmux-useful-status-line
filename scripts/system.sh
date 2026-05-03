#!/usr/bin/env bash
# CPU load / memory / disk health for tmux status bar.
# Silent when healthy, warns above threshold.
# macOS only.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$DIR/helpers.sh"

segment_enabled "system" || exit 0
is_darwin || exit 0

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

ICON_LOAD=$(get_tmux_option "@useful-icon-load" "")
ICON_MEM=$(get_tmux_option "@useful-icon-mem" "")
ICON_DISK=$(get_tmux_option "@useful-icon-disk" "󰋊")

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

load1=$(sysctl -n vm.loadavg | awk '{print $2}')
ncpu=$(sysctl -n hw.ncpu)
load_pct=$(awk -v l="$load1" -v n="$ncpu" 'BEGIN { printf "%d", (l/n)*100 }')
# Crit warnings get a leading "!" so users with deuteranopia/protanopia can
# distinguish warn (yellow→mustard) from crit (red→mustard) without color.
# Healthy values render in dim when an "always" mode is selected.
if [ "$load_pct" -ge "$LOAD_CRIT" ]; then
    out+=" #[fg=$CRIT]!$ICON_LOAD $load1"
elif [ "$load_pct" -ge "$LOAD_WARN" ]; then
    out+=" #[fg=$WARN]$ICON_LOAD $load1"
elif should_show_healthy load; then
    out+=" #[fg=$DIM]$ICON_LOAD $load1"
fi

mem_free=$(memory_pressure | awk '/System-wide memory free percentage/ {gsub("%",""); print $5}')
mem=$(( 100 - ${mem_free:-0} ))
if [ "$mem" -ge "$MEM_CRIT" ]; then
    out+=" #[fg=$CRIT]!$ICON_MEM ${mem}%"
elif [ "$mem" -ge "$MEM_WARN" ]; then
    out+=" #[fg=$WARN]$ICON_MEM ${mem}%"
elif should_show_healthy mem; then
    out+=" #[fg=$DIM]$ICON_MEM ${mem}%"
fi

disk=$(df -h / | awk 'NR==2 {gsub("%",""); print $5}')
if [ "$disk" -ge "$DISK_CRIT" ]; then
    out+=" #[fg=$CRIT]!$ICON_DISK ${disk}%"
elif [ "$disk" -ge "$DISK_WARN" ]; then
    out+=" #[fg=$WARN]$ICON_DISK ${disk}%"
elif should_show_healthy disk; then
    out+=" #[fg=$DIM]$ICON_DISK ${disk}%"
fi

[ -n "$out" ] && out+="#[fg=default]"

printf "%s" "$out" | tee "$CACHE_FILE"
