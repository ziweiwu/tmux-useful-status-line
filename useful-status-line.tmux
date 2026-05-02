#!/usr/bin/env bash
# Entry point for tmux-useful-status-line.
# Replaces #{useful_*} placeholders in status-left / status-right with
# real shell-out calls to scripts/*.sh.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

placeholders=(
    "\#{useful_spotify}"
    "\#{useful_system}"
    "\#{useful_weather}"
    "\#{useful_battery}"
)

replacements=(
    "#($CURRENT_DIR/scripts/spotify.sh)"
    "#($CURRENT_DIR/scripts/system.sh)"
    "#($CURRENT_DIR/scripts/weather.sh)"
    "#($CURRENT_DIR/scripts/battery.sh)"
)

interpolate() {
    local s="$1"
    for ((i=0; i<${#placeholders[@]}; i++)); do
        s="${s//${placeholders[$i]}/${replacements[$i]}}"
    done
    echo "$s"
}

update_option() {
    local opt="$1"
    local val
    val=$(tmux show-option -gqv "$opt")
    [ -z "$val" ] && return
    tmux set-option -gq "$opt" "$(interpolate "$val")"
}

update_option "status-left"
update_option "status-right"
