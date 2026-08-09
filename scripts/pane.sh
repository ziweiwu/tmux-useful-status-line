#!/usr/bin/env bash
# Active-pane command indicator — like lualine's "filename" section.
# Hidden when the pane is running a default shell (uninteresting); shown
# when running anything else (vim, claude, ssh, docker, kubectl, etc.).
# This gives situational awareness about what you're focused on.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Guarded so bin/useful-status can source helpers once and then source all
# six segments without each re-running the config snapshot.
# shellcheck source=helpers.sh
[ -n "${USEFUL_HELPERS_LOADED:-}" ] || source "$DIR/helpers.sh"

# The body lives in a function so the six segments can share one process.
# Deliberately not re-indented: it keeps this diff reviewable and leaves
# column-0 heredoc terminators intact.
useful_segment_pane() {
segment_enabled "pane" || return 0

# The pane's foreground command, taken from the config snapshot helpers.sh
# already fetched — no extra tmux round-trip. Empty outside tmux, which
# correctly renders this segment as nothing.
cmd=$(useful_pane_command)
[ -z "$cmd" ] && return 0

# Hide pure version-number strings (e.g. Claude Code's pane_current_command
# exposes "2.1.126" — its CLI version). Noisy and rarely actionable.
if [[ "$cmd" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
    return 0
fi

# Hide list — running these is "boring" so we suppress the segment.
HIDE_LIST=$(get_tmux_option "@useful-pane-hide" "zsh bash sh fish dash tmux")
for s in $HIDE_LIST; do
    if [ "$cmd" = "$s" ]; then
        return 0
    fi
done

# Truncate long command names so a long process name doesn't blow out the bar.
# Budget is in terminal cells — see useful_truncate in helpers.sh.
MAX_LEN=$(get_tmux_option "@useful-pane-max-len" 16)
useful_truncate "$cmd" "$MAX_LEN"
cmd="$USEFUL_TRUNC"

DIM=$(color_dim)
ICON=$(get_tmux_option "@useful-pane-icon" "")
printf " #[fg=%s]%s %s#[fg=default]" "$DIM" "$ICON" "$cmd"
}

# tmux calls this script directly via #(...); the driver sources it instead.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    useful_segment_pane
fi
