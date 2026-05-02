#!/usr/bin/env bash
# CPU load / memory / disk health for tmux status bar.
# Silent when healthy, warns above threshold.
# macOS only.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$DIR/helpers.sh"

CACHE_FILE="${TMUX_USEFUL_CACHE_DIR:-/tmp}/tmux-useful-system-cache"
cache_check "$CACHE_FILE" 5 && exit 0

WARN=$(color_warn)
CRIT=$(color_crit)

LOAD_WARN=$(get_tmux_option "@useful-load-warn" 70)
LOAD_CRIT=$(get_tmux_option "@useful-load-crit" 100)
MEM_WARN=$(get_tmux_option "@useful-mem-warn" 75)
MEM_CRIT=$(get_tmux_option "@useful-mem-crit" 90)
DISK_WARN=$(get_tmux_option "@useful-disk-warn" 80)
DISK_CRIT=$(get_tmux_option "@useful-disk-crit" 95)

ICON_LOAD=$(get_tmux_option "@useful-icon-load" "")
ICON_MEM=$(get_tmux_option "@useful-icon-mem" "")
ICON_DISK=$(get_tmux_option "@useful-icon-disk" "󰋊")

out=""

load1=$(sysctl -n vm.loadavg | awk '{print $2}')
ncpu=$(sysctl -n hw.ncpu)
load_pct=$(awk -v l="$load1" -v n="$ncpu" 'BEGIN { printf "%d", (l/n)*100 }')
# Each warning prefixes a single space; no trailing space. Chained warnings
# end up "  icon1 val1 icon2 val2" (single space between segments).
if [ "$load_pct" -ge "$LOAD_CRIT" ]; then
    out+=" #[fg=$CRIT]$ICON_LOAD $load1"
elif [ "$load_pct" -ge "$LOAD_WARN" ]; then
    out+=" #[fg=$WARN]$ICON_LOAD $load1"
fi

mem_free=$(memory_pressure | awk '/System-wide memory free percentage/ {gsub("%",""); print $5}')
mem=$(( 100 - ${mem_free:-0} ))
if [ "$mem" -ge "$MEM_CRIT" ]; then
    out+=" #[fg=$CRIT]$ICON_MEM ${mem}%"
elif [ "$mem" -ge "$MEM_WARN" ]; then
    out+=" #[fg=$WARN]$ICON_MEM ${mem}%"
fi

disk=$(df -h / | awk 'NR==2 {gsub("%",""); print $5}')
if [ "$disk" -ge "$DISK_CRIT" ]; then
    out+=" #[fg=$CRIT]$ICON_DISK ${disk}%"
elif [ "$disk" -ge "$DISK_WARN" ]; then
    out+=" #[fg=$WARN]$ICON_DISK ${disk}%"
fi

[ -n "$out" ] && out+="#[fg=default]"

printf "%s" "$out" | tee "$CACHE_FILE"
