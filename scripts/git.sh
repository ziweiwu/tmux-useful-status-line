#!/usr/bin/env bash
# Git branch + dirty indicator for tmux status bar.
# Empty when not in a repo. Branch name + "*" when working tree is dirty.
# Cached 3s — git status is fast but not free.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=helpers.sh
source "$DIR/helpers.sh"

segment_enabled "git" || exit 0

# tmux's #{pane_current_path} is what the active pane considers cwd. We pass
# it via the environment when called from #(...). Fall back to the script's
# own cwd otherwise (e.g., ad-hoc invocation from the shell).
cwd="${TMUX_PANE_CURRENT_PATH:-$(tmux display -p '#{pane_current_path}' 2>/dev/null)}"
[ -z "$cwd" ] && cwd="$PWD"

# Cache key: hash the cwd so each repo has its own short-TTL cache.
cwd_hash=$(printf "%s" "$cwd" | shasum 2>/dev/null | cut -c1-8)
CACHE_FILE="$(useful_cache_dir)/git-${cwd_hash}"
cache_check "$CACHE_FILE" 3 && exit 0

DIM=$(color_dim)
WARN=$(color_warn)
ICON=$(get_tmux_option "@useful-git-icon" "")
DIRTY_MARK=$(get_tmux_option "@useful-git-dirty-mark" "*")

# Resolve to top-level once, then ask for branch + porcelain status from there.
# This lets us cache by the repo path rather than the pane's exact cwd, but
# we still cache by the pane cwd because that's cheaper to key on.
top=$(git -C "$cwd" rev-parse --show-toplevel 2>/dev/null)
if [ -z "$top" ]; then
    : >"$CACHE_FILE"
    exit 0
fi

branch=$(git -C "$top" symbolic-ref --short HEAD 2>/dev/null)
# Detached HEAD: show the short SHA.
if [ -z "$branch" ]; then
    branch=$(git -C "$top" rev-parse --short HEAD 2>/dev/null)
    [ -n "$branch" ] && branch="@${branch}"
fi
[ -z "$branch" ] && { : >"$CACHE_FILE"; exit 0; }

# Truncate long branch names so a feature/very-long-name doesn't blow out the bar.
MAX_BRANCH_LEN=$(get_tmux_option "@useful-git-max-branch-len" 24)
if [ "${#branch}" -gt "$MAX_BRANCH_LEN" ]; then
    branch="${branch:0:$((MAX_BRANCH_LEN - 1))}…"
fi

# Dirty: any uncommitted changes (staged, unstaged, or untracked).
dirty=""
if [ -n "$(git -C "$top" status --porcelain 2>/dev/null)" ]; then
    dirty="$DIRTY_MARK"
fi

if [ -n "$dirty" ]; then
    color="$WARN"
else
    color="$DIM"
fi

printf " #[fg=%s]%s %s%s#[fg=default]" "$color" "$ICON" "$branch" "$dirty" | tee "$CACHE_FILE"
