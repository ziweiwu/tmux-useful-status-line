#!/usr/bin/env bash
# Battery for tmux status bar — dynamic glyph + state color.
# macOS only (uses pmset).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$DIR/helpers.sh"

CACHE_FILE="${TMUX_USEFUL_CACHE_DIR:-/tmp}/tmux-useful-battery-cache"
cache_check "$CACHE_FILE" 10 && exit 0

OK=$(color_ok)
WARN=$(color_warn)
CRIT=$(color_crit)

BATT_WARN=$(get_tmux_option "@useful-batt-warn" 40)
BATT_CRIT=$(get_tmux_option "@useful-batt-crit" 20)
# Visibility mode: always | discharging-or-low | low-only
SHOW_WHEN=$(get_tmux_option "@useful-batt-show-when" "always")
FULL_PCT=$(get_tmux_option "@useful-batt-full-pct" 95)

batt=$(pmset -g batt 2>/dev/null)
[ -z "$batt" ] && exit 0

pct=$(echo "$batt" | grep -oE '[0-9]{1,3}%' | head -1 | tr -d '%')
[ -z "$pct" ] && exit 0

charging=0
echo "$batt" | grep -q "AC Power" && charging=1

# Honor visibility mode before doing any further work.
case "$SHOW_WHEN" in
    always)
        ;;
    low-only)
        if [ "$charging" -eq 1 ] || [ "$pct" -ge "$BATT_WARN" ]; then
            : > "$CACHE_FILE"
            exit 0
        fi
        ;;
    discharging-or-low|*)
        # Hide when fully charged AND on AC — the most boring state.
        if [ "$charging" -eq 1 ] && [ "$pct" -ge "$FULL_PCT" ]; then
            : > "$CACHE_FILE"
            exit 0
        fi
        ;;
esac

if [ "$charging" -eq 1 ]; then
    glyph="󰂄"
elif [ "$pct" -ge 90 ]; then glyph="󰂂"
elif [ "$pct" -ge 75 ]; then glyph="󰂀"
elif [ "$pct" -ge 60 ]; then glyph="󰁾"
elif [ "$pct" -ge 45 ]; then glyph="󰁼"
elif [ "$pct" -ge 30 ]; then glyph="󰁺"
elif [ "$pct" -ge 15 ]; then glyph="󰁻"
else glyph="󰂃"; fi

if [ "$charging" -eq 0 ] && [ "$pct" -lt "$BATT_CRIT" ]; then
    color="$CRIT"
elif [ "$charging" -eq 0 ] && [ "$pct" -lt "$BATT_WARN" ]; then
    color="$WARN"
else
    color="$OK"
fi

printf "#[fg=%s]%s %s%%#[fg=default]" "$color" "$glyph" "$pct" | tee "$CACHE_FILE"
