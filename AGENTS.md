# AGENTS.md

For LLM coding agents (and humans) working in this repo.

**Project:** `tmux-useful-status-line` is a tmux status-line plugin that's silent when the system is healthy and loud when it isn't. Six segments under `scripts/` (`system`, `battery`, `weather`, `spotify`, `git`, `pane`), each a single bash script that emits tmux-format-coloured text or empty. macOS + Linux for `system`/`battery`; spotify is macOS-only.

## Conventions

- **Bash**, `#!/usr/bin/env bash`. `shellcheck -x` must pass — CI enforces.
- **Source order:** `source "$DIR/helpers.sh"` first. That brings in `get_tmux_option`, `cache_check`, `useful_cache_dir`, `is_darwin`/`is_linux`, `segment_enabled`, and `color_*`.
- **No external deps** beyond what each platform ships. No jq, python, node.
- **Cache aggressively.** Every script that hits a slow source caches in `$(useful_cache_dir)` and short-circuits with `cache_check`.
- **Configuration only via tmux options** (`@useful-*`), never env vars. Read with `get_tmux_option "@useful-foo" "default"`.
- **Color via `#[fg=...]` foreground only.** No background blocks. End every coloured run with `#[fg=default]`.

## Adding a segment

1. `scripts/foo.sh` — source helpers, `segment_enabled "foo" || exit 0`, `cache_check`, do work, emit either empty or `" <icon> <value>"` (single leading space, no trailing).
2. Register the placeholder in `useful-status-line.tmux`.
3. Add `tests/test_foo.bats` covering: healthy → empty; warn / crit bands; cache reuse; `@useful-foo-enabled off` → empty.
4. Stub any new external command in `tests/stubs/`.
5. Update README's segment table + Configuration block + CHANGELOG.
6. `make check`.

## Avoid

- Background-color blocks (decoration, not state).
- Always-on output for healthy state — defeats the design contract.
- Hard-coded hex colors — use `color_*` helpers so themes still apply.
- Writing outside `$(useful_cache_dir)`.
- Bash 4-only syntax — macOS ships bash 3.2.

## Pitfalls (load-bearing)

- `${var:offset:length}` is bytewise unless `LC_CTYPE` is UTF-8. `helpers.sh` sets a UTF-8 locale at source time.
- `stat -f %m` is BSD; GNU is `stat -c %Y`. Use `file_mtime` from helpers, not raw `stat`.
- tmux strftime (`%H`, `%S`) runs on format strings, not on `#()` output, so scripts can emit literal `%` freely.
- `#[fg=default]` reset is mandatory at the end of any coloured run, otherwise color bleeds into adjacent segments.

When something isn't covered above, the existing tests are the executable spec.
