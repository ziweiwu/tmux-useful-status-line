#!/usr/bin/env bash
# Shared helpers for tmux-useful-status-line scripts.

# Force a UTF-8 locale so bash's ${var:offset:length} slices on character
# boundaries instead of bytes. Without this, CJK/RTL track names get cut
# mid-byte during the Spotify slide, producing mojibake.
case "${LC_ALL:-${LC_CTYPE:-${LANG:-}}}" in
    *UTF-8*|*utf8*) ;;
    *)
        if locale -a 2>/dev/null | grep -qi '^C\.UTF-8$'; then
            export LC_ALL=C.UTF-8
        elif locale -a 2>/dev/null | grep -qi '^en_US\.UTF-8$'; then
            export LC_ALL=en_US.UTF-8
        fi
        ;;
esac

# Portable file-mtime in seconds. BSD/macOS uses `stat -f %m`, GNU uses
# `stat -c %Y`. Try BSD first (we're macOS-first); fall back to GNU.
file_mtime() {
    stat -f %m "$1" 2>/dev/null || stat -c %Y "$1" 2>/dev/null
}

# OS detection. Tests can override with TMUX_USEFUL_OS_OVERRIDE to exercise
# Linux code paths on a macOS CI runner.
useful_os() {
    printf "%s" "${TMUX_USEFUL_OS_OVERRIDE:-$(uname -s 2>/dev/null)}"
}

is_darwin() { [ "$(useful_os)" = "Darwin" ]; }
is_linux()  { [ "$(useful_os)" = "Linux" ]; }

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
    local mtime age
    mtime=$(file_mtime "$file")
    [ -z "$mtime" ] && return 1
    age=$(( $(date +%s) - mtime ))
    [ "$age" -lt "$max_age" ] || return 1
    cat "$file"
    return 0
}

# Default palette = Nord. Other themes are selected via @useful-theme.
# Individual @useful-color-* options always win over the theme's defaults.
default_color_ok="#a3be8c"
default_color_warn="#ebcb8b"
default_color_crit="#bf616a"
default_color_accent="#b48ead"
default_color_dim="#7b8696"

# Theme presets. All values keep WCAG AA contrast vs typical dark terminal
# backgrounds for the dim/accent (the readability-critical tones).
case "$(get_tmux_option "@useful-theme" "")" in
    nord|"")
        ;;  # defaults already match Nord
    catppuccin|catppuccin-mocha)
        default_color_ok="#a6e3a1"
        default_color_warn="#f9e2af"
        default_color_crit="#f38ba8"
        default_color_accent="#cba6f7"
        default_color_dim="#9399b2"
        ;;
    gruvbox|gruvbox-dark)
        default_color_ok="#b8bb26"
        default_color_warn="#fabd2f"
        default_color_crit="#fb4934"
        default_color_accent="#d3869b"
        default_color_dim="#a89984"
        ;;
    everforest|everforest-dark)
        default_color_ok="#a7c080"
        default_color_warn="#dbbc7f"
        default_color_crit="#e67e80"
        default_color_accent="#d699b6"
        default_color_dim="#9da9a0"
        ;;
    vitesse|vitesse-dark)
        default_color_ok="#4d9375"
        default_color_warn="#d4976c"
        default_color_crit="#cb7676"
        default_color_accent="#a8b1ff"
        default_color_dim="#8a8d96"
        ;;
    rose-pine|rosepine)
        default_color_ok="#9ccfd8"
        default_color_warn="#f6c177"
        default_color_crit="#eb6f92"
        default_color_accent="#c4a7e7"
        default_color_dim="#908caa"
        ;;
esac

# Cache directory: namespaced per UID so multi-user hosts don't collide, and
# per tmux socket so multiple servers on the same host can't stomp each other.
useful_cache_dir() {
    local override
    override=$(get_tmux_option "@useful-cache-dir" "")
    if [ -n "$override" ]; then
        printf "%s" "$override"
        return
    fi
    if [ -n "${TMUX_USEFUL_CACHE_DIR:-}" ]; then
        printf "%s" "$TMUX_USEFUL_CACHE_DIR"
        return
    fi
    local base="${TMPDIR:-/tmp}"
    # Strip trailing slash for predictable concatenation.
    base="${base%/}"
    local socket_id=""
    if [ -n "${TMUX:-}" ]; then
        socket_id=$(printf "%s" "${TMUX%%,*}" | shasum 2>/dev/null | cut -c1-8)
    fi
    local dir="$base/tmux-useful-${UID:-$(id -u)}-${socket_id:-default}"
    mkdir -p "$dir" 2>/dev/null
    printf "%s" "$dir"
}

color_ok() { get_tmux_option "@useful-color-ok" "$default_color_ok"; }
color_warn() { get_tmux_option "@useful-color-warn" "$default_color_warn"; }
color_crit() { get_tmux_option "@useful-color-crit" "$default_color_crit"; }
color_accent() { get_tmux_option "@useful-color-accent" "$default_color_accent"; }
color_dim() { get_tmux_option "@useful-color-dim" "$default_color_dim"; }

# Per-segment enable/disable. Returns 0 if enabled (default), 1 if disabled.
segment_enabled() {
    local seg="$1"
    local val
    val=$(get_tmux_option "@useful-${seg}-enabled" "on")
    case "$val" in
        off|false|0|no) return 1 ;;
        *) return 0 ;;
    esac
}
