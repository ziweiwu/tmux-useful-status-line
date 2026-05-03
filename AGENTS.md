# AGENTS.md

For LLM coding agents (and humans) working in this repo.

## Project shape

`tmux-useful-status-line` is a tmux status-line plugin (macOS + Linux for `system` and `battery`; spotify is macOS-only). Design contract: **silent when healthy, loud when not**. Color is reserved for state, never decoration.

Each segment is a single bash script under `scripts/` that emits tmux-format-coloured text or empty.

## Conventions

- **Bash**, `#!/usr/bin/env bash`. `shellcheck -x` must pass — CI enforces.
- **Source order:** `source "$DIR/helpers.sh"` first; that brings in `get_tmux_option`, `cache_check`, `useful_cache_dir`, `is_darwin`/`is_linux`, `segment_enabled`, and the `color_*` helpers.
- **No external deps** beyond what each platform ships (`pmset`, `sysctl`, `memory_pressure`, `pgrep`, `osascript` on macOS; `/proc`, `free`, `nproc` on Linux). No jq, python, node.
- **Cache aggressively.** Every script that hits a slow source caches its output in `$(useful_cache_dir)` and short-circuits with `cache_check`.
- **Configuration only via tmux options** (`@useful-*`), not env vars. Read with `get_tmux_option "@useful-foo" "default"`.
- **Color via `#[fg=...]` foreground only.** No background blocks. Always end a coloured run with `#[fg=default]`.

## Adding a segment

1. `scripts/foo.sh` — `source` helpers, `segment_enabled "foo" || exit 0`, `cache_check`, do work, emit either empty or ` <icon> <value>` (single leading space, no trailing).
2. Register the placeholder in `useful-status-line.tmux`.
3. Add `tests/test_foo.bats` covering: healthy → empty; warn / crit bands; cache reuse; `@useful-foo-enabled off` → empty.
4. Add stubs to `tests/stubs/` for any new external command.
5. README placeholder table + Configuration block + CHANGELOG entry.
6. `make check`.

## Things to avoid

- Background-color blocks (decoration).
- Always-on output for healthy state.
- Hard-coded hex colors — use `color_*` helpers so themes still apply.
- Writing outside `$(useful_cache_dir)`.
- Bash 4-only syntax — macOS ships bash 3.2.

## Pitfalls (load-bearing)

- `${var:offset:length}` is bytewise unless `LC_CTYPE` is UTF-8. `helpers.sh` sets a UTF-8 locale at source time — keep it that way or CJK/RTL breaks.
- `stat -f %m` is BSD; GNU is `stat -c %Y`. Use `file_mtime` from helpers, not `stat` directly.
- tmux strftime (`%H`, `%S`) runs on format strings, not on `#()` output, so scripts can emit literal `%` freely.
- The `#[fg=default]` reset is mandatory at the end of any coloured run, otherwise color bleeds.

When something isn't covered above, look at the existing tests — they're the executable spec.
