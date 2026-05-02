#!/usr/bin/env bash
# Shared helpers for tmux-useful-status-line scripts.

get_tmux_option() {
    local option="$1"
    local default_value="$2"
    local val
    val=$(tmux show-option -gqv "$option" 2>/dev/null)
    if [ -z "$val" ]; then
        echo "$default_value"
    else
        echo "$val"
    fi
}

# Cache helper: prints cache contents to stdout and exits 0 if fresh.
# Usage: cache_check "$CACHE_FILE" "$MAX_AGE_SEC" || run_and_cache
cache_check() {
    local file="$1"
    local max_age="$2"
    [ -f "$file" ] || return 1
    local age
    age=$(( $(date +%s) - $(stat -f %m "$file") ))
    [ "$age" -lt "$max_age" ] || return 1
    cat "$file"
    return 0
}

# Default colors (Nord-ish but neutral enough for any palette).
default_color_ok="#a3be8c"
default_color_warn="#ebcb8b"
default_color_crit="#bf616a"
default_color_accent="#b48ead"
default_color_dim="#4c566a"

color_ok() { get_tmux_option "@useful-color-ok" "$default_color_ok"; }
color_warn() { get_tmux_option "@useful-color-warn" "$default_color_warn"; }
color_crit() { get_tmux_option "@useful-color-crit" "$default_color_crit"; }
color_accent() { get_tmux_option "@useful-color-accent" "$default_color_accent"; }
color_dim() { get_tmux_option "@useful-color-dim" "$default_color_dim"; }
