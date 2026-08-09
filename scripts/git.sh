#!/usr/bin/env bash
# Git branch + dirty indicator for tmux status bar.
# Empty when not in a repo. Branch name + "*" when working tree is dirty.
# Cached 3s — git status is fast but not free.

DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# Guarded so bin/useful-status can source helpers once and then source all
# six segments without each re-running the config snapshot.
# shellcheck source=helpers.sh
[ -n "${USEFUL_HELPERS_LOADED:-}" ] || source "$DIR/helpers.sh"

# The body lives in a function so the six segments can share one process.
# Deliberately not re-indented: it keeps this diff reviewable and leaves
# column-0 heredoc terminators intact.
useful_segment_git() {
segment_enabled "git" || return 0

# The active pane's cwd. useful_pane_path reads it from the config snapshot
# helpers.sh already took, so this costs no extra tmux round-trip; it honors
# TMUX_PANE_CURRENT_PATH when a caller injects one. Falls back to the script's
# own cwd outside tmux (e.g., ad-hoc invocation from the shell).
cwd="$(useful_pane_path)"
[ -z "$cwd" ] && cwd="$PWD"

# Cache key: hash the cwd so each repo has its own short-TTL cache.
cwd_hash=$(printf "%s" "$cwd" | shasum 2>/dev/null | cut -c1-8)
CACHE_FILE="$(useful_cache_dir)/git-${cwd_hash}"
cache_check "$CACHE_FILE" 3 && return 0

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
    return 0
fi

branch=$(git -C "$top" symbolic-ref --short HEAD 2>/dev/null)
# Detached HEAD: show the short SHA.
if [ -z "$branch" ]; then
    branch=$(git -C "$top" rev-parse --short HEAD 2>/dev/null)
    [ -n "$branch" ] && branch="@${branch}"
fi
[ -z "$branch" ] && { : >"$CACHE_FILE"; return 0; }

# Truncate long branch names so a feature/very-long-name doesn't blow out the
# bar. The budget is in terminal CELLS, not characters: a 24-character CJK
# branch name occupies 40 cells, and ${#branch} would happily pass it through.
MAX_BRANCH_LEN=$(get_tmux_option "@useful-git-max-branch-len" 24)
useful_truncate "$branch" "$MAX_BRANCH_LEN"
branch="$USEFUL_TRUNC"

# Dirty: any uncommitted changes. In monorepos, scanning untracked files can
# be slow (seconds); the @useful-git-skip-untracked option trades accuracy
# (untracked files won't trigger the dirty mark) for speed.
dirty=""
if [ "$(get_tmux_option "@useful-git-skip-untracked" "off")" = "on" ]; then
    porcelain_args="--porcelain --untracked-files=no"
else
    porcelain_args="--porcelain"
fi
# shellcheck disable=SC2086
if [ -n "$(git -C "$top" status $porcelain_args 2>/dev/null)" ]; then
    dirty="$DIRTY_MARK"
fi

if [ -n "$dirty" ]; then
    color="$WARN"
else
    color="$DIM"
fi

printf " #[fg=%s]%s %s%s#[fg=default]" "$color" "$ICON" "$branch" "$dirty" | tee "$CACHE_FILE"
}

# tmux calls this script directly via #(...); the driver sources it instead.
if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    useful_segment_git
fi
