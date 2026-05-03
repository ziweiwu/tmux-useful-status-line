#!/usr/bin/env bash
# Battery for tmux status bar — dynamic glyph + state color.
# macOS only (uses pmset).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$DIR/helpers.sh"

segment_enabled "battery" || exit 0
is_darwin || exit 0

CACHE_FILE="$(useful_cache_dir)/battery"
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

# Glyphs are overrideable for users without a Nerd Font. The defaults are
# Nerd Font codepoints; the @useful-batt-icons-ascii toggle swaps to ASCII
# fallbacks that render in any terminal.
if [ "$(get_tmux_option "@useful-batt-icons-ascii" "off")" = "on" ]; then
    icon_charging="+"
    icon_full="[####]"
    icon_high="[### ]"
    icon_mid="[##  ]"
    icon_low="[#   ]"
    icon_empty="[!]"
else
    icon_charging=$(get_tmux_option "@useful-batt-icon-charging" "󰂄")
    icon_full=$(get_tmux_option "@useful-batt-icon-full" "󰂂")
    icon_high=$(get_tmux_option "@useful-batt-icon-high" "󰂀")
    icon_mid=$(get_tmux_option "@useful-batt-icon-mid" "󰁾")
    icon_low=$(get_tmux_option "@useful-batt-icon-low" "󰁺")
    icon_empty=$(get_tmux_option "@useful-batt-icon-empty" "󰂃")
fi

if [ "$charging" -eq 1 ]; then
    glyph="$icon_charging"
elif [ "$pct" -ge 90 ]; then glyph="$icon_full"
elif [ "$pct" -ge 60 ]; then glyph="$icon_high"
elif [ "$pct" -ge 30 ]; then glyph="$icon_mid"
elif [ "$pct" -ge 15 ]; then glyph="$icon_low"
else glyph="$icon_empty"; fi

if [ "$charging" -eq 0 ] && [ "$pct" -lt "$BATT_CRIT" ]; then
    color="$CRIT"
elif [ "$charging" -eq 0 ] && [ "$pct" -lt "$BATT_WARN" ]; then
    color="$WARN"
else
    color="$OK"
fi

# Crit gets a non-color "!" prefix for color-blind users.
prefix=""
if [ "$charging" -eq 0 ] && [ "$pct" -lt "$BATT_CRIT" ]; then
    prefix="!"
fi

printf " #[fg=%s]%s%s %s%%#[fg=default]" "$color" "$prefix" "$glyph" "$pct" | tee "$CACHE_FILE"
