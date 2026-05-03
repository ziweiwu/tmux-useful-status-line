#!/usr/bin/env bash
# Active-pane command indicator — like lualine's "filename" section.
# Hidden when the pane is running a default shell (uninteresting); shown
# when running anything else (vim, claude, ssh, docker, kubectl, etc.).
# This gives situational awareness about what you're focused on.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$DIR/helpers.sh"

segment_enabled "pane" || exit 0

# Tmux's #{pane_current_command} is fast — it queries tmux's own state.
cmd=$(tmux display -p '#{pane_current_command}' 2>/dev/null)
[ -z "$cmd" ] && exit 0

# Hide pure version-number strings (e.g. Claude Code's pane_current_command
# exposes "2.1.126" — its CLI version). Noisy and rarely actionable.
if [[ "$cmd" =~ ^[0-9]+(\.[0-9]+)+$ ]]; then
    exit 0
fi

# Hide list — running these is "boring" so we suppress the segment.
HIDE_LIST=$(get_tmux_option "@useful-pane-hide" "zsh bash sh fish dash tmux")
for s in $HIDE_LIST; do
    if [ "$cmd" = "$s" ]; then
        exit 0
    fi
done

# Truncate long command names so a long process name doesn't blow out the bar.
MAX_LEN=$(get_tmux_option "@useful-pane-max-len" 16)
if [ "${#cmd}" -gt "$MAX_LEN" ]; then
    cmd="${cmd:0:$((MAX_LEN - 1))}…"
fi

DIM=$(color_dim)
ICON=$(get_tmux_option "@useful-pane-icon" "")
printf " #[fg=%s]%s %s#[fg=default]" "$DIM" "$ICON" "$cmd"
