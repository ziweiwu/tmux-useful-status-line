# AGENTS.md

For LLM coding agents (and humans) working in this repo.

**Project:** `tmux-useful-status-line` is a tmux status-line plugin that's silent when the system is healthy and loud when it isn't. Six segments under `scripts/` (`system`, `battery`, `weather`, `spotify`, `git`, `pane`), each a single bash script that emits tmux-format-coloured text or empty. macOS + Linux for `system`/`battery`; spotify is macOS-only.

## Conventions

- **Bash**, `#!/usr/bin/env bash`. `shellcheck -x` must pass — CI enforces.
- **Source order:** `source "$DIR/helpers.sh"` first. That brings in `get_tmux_option`, `cache_check`, `useful_cache_dir`, `is_darwin`/`is_linux`, `segment_enabled`, and `color_*`.
- **No external deps** beyond what each platform ships. No jq, python, node.
- **Cache aggressively.** Every script that hits a slow source caches in `$(useful_cache_dir)` and short-circuits with `cache_check`.
- **Configuration only via tmux options** (`@useful-*`), never env vars. Read with `get_tmux_option "@useful-foo" "default"`, and **register the option name in `USEFUL_OPT_MANIFEST` in `helpers.sh`** — `tests/test_config.bats` fails CI otherwise. Unregistered names still work, they just cost a tmux fork each.
- **Color via `#[fg=...]` foreground only.** No background blocks. End every coloured run with `#[fg=default]`.

## Architecture

Three seams isolate the segments from tmux, so the same code drives a shell
prompt or waybar:

- **Config** — `get_tmux_option`. One `display-message -p` snapshot at
  `helpers.sh` source time populates `USEFUL_OPT_*`; every later lookup is a
  variable read. Taken in the main shell deliberately, so `$(color_ok)`-style
  command substitutions inherit it instead of each forking tmux. The snapshot
  is capability-checked, not version-gated: if tmux returns the `#{@...}`
  tokens verbatim, or returns nothing while `show-options -g` proves options
  exist, the batch is refused and lookups go per-option. Keep both guards if
  you touch `useful_config_load` — they are what lets us support tmux versions
  whose `#{@user-option}` support we cannot confirm.
- **Pane context** — `useful_pane_path` / `useful_pane_command`, from the same
  snapshot.
- **Rendering** — segments always emit tmux markup; it is the internal wire
  format. `useful_render <mode> <text>` translates it on the way out. Don't
  thread a renderer through segment code.

`bin/useful-status` sources helpers once, then sources each segment file and
calls its `useful_segment_<name>` function inside a command substitution. That
subshell is load-bearing: segment bodies were written as scripts, so their
variables are globals that would otherwise collide.

## Adding a segment

1. `scripts/foo.sh` — source helpers via the `USEFUL_HELPERS_LOADED` guard, wrap the body in `useful_segment_foo() { ... }` with a `[ "${BASH_SOURCE[0]}" = "${0}" ]` standalone guard at the bottom, `segment_enabled "foo" || return 0`, `cache_check`, do work, emit either empty or `" <icon> <value>"` (single leading space, no trailing). Use `return`, never `exit` — the body runs as a function.
2. Register the placeholder in `useful-status-line.tmux` and add the name to `ALL_SEGMENTS` in `bin/useful-status`.
3. Add every new `@useful-*` option to `USEFUL_OPT_MANIFEST` in `scripts/helpers.sh`.
4. Add `tests/test_foo.bats` covering: healthy → empty; warn / crit bands; cache reuse; `@useful-foo-enabled off` → empty.
5. Stub any new external command in `tests/stubs/`.
6. Update README's segment table + Configuration block + CHANGELOG.
7. `make check`.

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
- **Characters are not cells.** `${#s}` and `${s:0:n}` count characters; the status bar's budget is display columns. A CJK glyph is 2 cells, a combining mark 0, and `U+FE0F` widens the glyph before it. Never truncate by hand — use `useful_truncate` / `useful_window` from `helpers.sh`.
- **On bash 3.2, `"$VAR…"` is a trap.** An unbraced variable followed by a multibyte literal swallows that literal's lead byte into the variable name — `"$USEFUL_WINDOW…"` emitted two stray bytes instead of an ellipsis. Always brace: `"${VAR}…"`. Every truncation site in this repo is one of these.
- **macOS `df` lies about `/`.** The Capacity column describes the sealed read-only APFS system snapshot, not your data; it sat at 2% on a 31%-full disk. Compute total-minus-available on Darwin. Linux's `Use%` is fine.
- **Codepoints are unavailable in bash 3.2**: `printf '%d' "'X"` returns the first *byte*, signed. `useful_utf8_decode` decodes UTF-8 by hand under a function-local `LC_ALL=C`, which bash restores on return.

When something isn't covered above, the existing tests are the executable spec.
