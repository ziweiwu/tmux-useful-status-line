#!/usr/bin/env bash
# Entry point for tmux-useful-status-line.
# Replaces #{useful_*} placeholders in status-left / status-right with
# real shell-out calls to scripts/*.sh, and (optionally) seeds a default
# layout for first-run users.

CURRENT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

# Defensive: tarball/zip downloads of the repo lose the executable bit.
# git clones preserve it, so this is a no-op in normal TPM use.
chmod +x "$CURRENT_DIR/scripts/"*.sh 2>/dev/null

placeholders=(
    "\#{useful_spotify}"
    "\#{useful_system}"
    "\#{useful_weather}"
    "\#{useful_battery}"
    "\#{useful_git}"
)

replacements=(
    "#($CURRENT_DIR/scripts/spotify.sh)"
    "#($CURRENT_DIR/scripts/system.sh)"
    "#($CURRENT_DIR/scripts/weather.sh)"
    "#($CURRENT_DIR/scripts/battery.sh)"
    "#($CURRENT_DIR/scripts/git.sh)"
)

interpolate() {
    local s="$1"
    local i
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

# If the user has opted into the bundled default layout, seed status-right
# (and a minimal status-left if they haven't customized it).
default_layout=$(tmux show-option -gqv "@useful-default-layout")
if [ "$default_layout" = "on" ]; then
    cur_right=$(tmux show-option -gqv "status-right")
    if [ -z "$cur_right" ] || [ "$cur_right" = " #{?client_prefix,#[reverse]<Prefix>#[noreverse],} \"#{=21:pane_title}\" %H:%M %d-%b-%y" ]; then
        tmux set-option -gq status-right \
            "#{useful_spotify}#{useful_git}#{useful_system}#{useful_weather}#{useful_battery} #[fg=#88c0d0]%H:%M #[default]"
    fi
    cur_left=$(tmux show-option -gqv "status-left")
    if [ -z "$cur_left" ] || [ "$cur_left" = "[#S] " ]; then
        tmux set-option -gq status-left "#[fg=#88c0d0,bold] #S #[default]"
    fi
fi

update_option "status-left"
update_option "status-right"
