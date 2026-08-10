#!/usr/bin/env bash
# Battery for tmux status bar — dynamic glyph + state color.
# macOS only (uses pmset).

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Guarded so bin/useful-status can source helpers once and then source all
# six segments without each re-running the config snapshot.
# shellcheck source=helpers.sh
[ -n "${USEFUL_HELPERS_LOADED:-}" ] || source "$DIR/helpers.sh"

# The body lives in a function so the six segments can share one process.
# Deliberately not re-indented: it keeps this diff reviewable and leaves
# column-0 heredoc terminators intact.
useful_segment_battery() {
segment_enabled "battery" || return 0

CACHE_FILE="$(useful_cache_dir)/battery"
cache_check "$CACHE_FILE" 10 && return 0

# Tests can override the Linux power-supply path via this env var.
SYS_POWER="${TMUX_USEFUL_SYS_POWER:-/sys/class/power_supply}"

OK=$(color_ok)
WARN=$(color_warn)
CRIT=$(color_crit)

BATT_WARN=$(get_tmux_option "@useful-batt-warn" 40)
BATT_CRIT=$(get_tmux_option "@useful-batt-crit" 20)
# Visibility mode: always | discharging-or-low | low-only
SHOW_WHEN=$(get_tmux_option "@useful-batt-show-when" "always")
FULL_PCT=$(get_tmux_option "@useful-batt-full-pct" 95)

pct=""
charging=0
if is_darwin; then
    batt=$(pmset -g batt 2>/dev/null)
    [ -z "$batt" ] && return 0
    pct=$(echo "$batt" | grep -oE '[0-9]{1,3}%' | head -1 | tr -d '%')
    echo "$batt" | grep -q "AC Power" && charging=1
elif is_linux; then
    # Find the first BAT* directory.
    bat_dir=""
    for d in "$SYS_POWER"/BAT0 "$SYS_POWER"/BAT1 "$SYS_POWER"/BAT2; do
        [ -f "$d/capacity" ] && { bat_dir="$d"; break; }
    done
    [ -z "$bat_dir" ] && return 0
    pct=$(cat "$bat_dir/capacity" 2>/dev/null)
    status=$(cat "$bat_dir/status" 2>/dev/null)
    case "$status" in
        Charging|Full|"Not charging") charging=1 ;;
    esac
else
    return 0
fi
[ -z "$pct" ] && return 0

# Honor visibility mode before doing any further work.
case "$SHOW_WHEN" in
    always)
        ;;
    low-only)
        if [ "$charging" -eq 1 ] || [ "$pct" -ge "$BATT_WARN" ]; then
            : > "$CACHE_FILE"
            return 0
        fi
        ;;
    discharging-or-low|*)
        # Hide when fully charged AND on AC — the most boring state.
        if [ "$charging" -eq 1 ] && [ "$pct" -ge "$FULL_PCT" ]; then
            : > "$CACHE_FILE"
            return 0
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

# Crit gets a non-color "!" prefix for color-blind users. Warn can too, via
# @useful-warn-prefix — battery renders in every state, so without it warn and
# ok are separated by hue alone.
WARN_PREFIX=$(get_tmux_option "@useful-warn-prefix" "")
case "$WARN_PREFIX" in none|off|false|0|no) WARN_PREFIX="" ;; esac
prefix=""
if [ "$charging" -eq 0 ] && [ "$pct" -lt "$BATT_CRIT" ]; then
    prefix="!"
elif [ "$charging" -eq 0 ] && [ "$pct" -lt "$BATT_WARN" ]; then
    prefix="$WARN_PREFIX"
fi

printf " #[fg=%s]%s%s %s%%#[fg=default]" "$color" "$prefix" "$glyph" "$pct" | tee "$CACHE_FILE"
}

# tmux calls this script directly via #(...); the driver sources it instead.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    useful_segment_battery
fi
