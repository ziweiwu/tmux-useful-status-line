# AGENTS.md

Guidance for LLM coding agents (Claude Code, Cline, Cursor, Aider, Gemini CLI, etc.) working in this repo.

## What this project is

`tmux-useful-status-line` is a tmux status-line plugin for macOS. The design principle is **state over decoration**: routine values stay hidden, color is reserved for state changes, and the bar pops only when something needs attention.

## Repo layout

```
.
├── useful-status-line.tmux   # TPM entry point — runs once on tmux load.
│                              # Replaces #{useful_*} placeholders in user's
│                              # status-left/status-right with #(...) shell-outs.
├── scripts/
│   ├── helpers.sh            # Shared bash: get_tmux_option, cache_check, color_*.
│   ├── system.sh             # CPU load / mem / disk — silent when healthy.
│   ├── battery.sh            # Battery glyph + state color.
│   ├── weather.sh            # wttr.in fetch with location/format-namespaced cache.
│   └── spotify.sh            # AppleScript Spotify now-playing, hidden when idle.
├── tests/
│   ├── test_helpers.bash     # Shared bats setup: stubs PATH, isolated cache dir.
│   ├── stubs/                # Fake tmux/sysctl/pmset/curl/osascript/etc.
│   └── test_*.bats           # One bats file per script.
├── .github/workflows/ci.yml  # macOS runner: shellcheck + bats on push/PR.
├── Makefile                  # `make test`, `make lint`, `make check`.
├── README.md                 # User-facing install + configuration.
└── LICENSE                   # MIT.
```

## Conventions

- **Bash, not zsh.** Every script starts with `#!/usr/bin/env bash`.
- **`shellcheck -x` must pass.** The `-x` follows `source` directives. CI enforces this.
- **No external deps beyond macOS-shipped tools** (`pmset`, `osascript`, `memory_pressure`, `sysctl`, `df`, `pgrep`) plus `curl` for weather. Don't introduce jq/python/node.
- **Cache aggressively.** Every script that calls a non-trivial command (osascript, curl, memory_pressure, top) writes a cache file under `${TMUX_USEFUL_CACHE_DIR:-/tmp}/tmux-useful-*-cache` and short-circuits on a fresh hit.
- **Silent when healthy.** Status segments emit empty output unless their metric is in a warning/critical band. The bar's job is to pop when it matters, not to display dashboards.
- **Configuration via tmux options**, not env vars at the user level. Read with `get_tmux_option "@useful-foo" "default"` from `helpers.sh`.
- **Color via `#[fg=...]`, not background blocks.** Background blocks all-the-time create visual noise; foreground color reserves attention for state.
- **Always end colored runs with `#[fg=default]`** so we don't bleed into adjacent segments.

## Adding a new metric

Checklist when introducing a new `scripts/foo.sh`:

1. Source `helpers.sh` from `$DIR/helpers.sh` (resolves at runtime regardless of cwd).
2. Define `CACHE_FILE="${TMUX_USEFUL_CACHE_DIR:-/tmp}/tmux-useful-foo-cache"` and short-circuit with `cache_check "$CACHE_FILE" <ttl> && exit 0`.
3. Read all tunables via `get_tmux_option "@useful-foo-..." "<default>"`.
4. Emit nothing in the healthy band. Only emit when the value crosses a configured threshold.
5. Add the placeholder to `useful-status-line.tmux`'s `placeholders`/`replacements` arrays.
6. Add a stub under `tests/stubs/` if your script invokes any external command not already stubbed.
7. Add `tests/test_foo.bats` with at least: healthy → empty; warn band; crit band; cache reuse; option override.
8. Update README's placeholder table and configuration sections.
9. Run `make check` before committing.

## Testing

- Framework: [`bats-core`](https://github.com/bats-core/bats-core).
- Stubs live in `tests/stubs/` and are prepended to `PATH` by `setup_test_env`. Stubs read `MOCK_*` env vars to vary their output between tests.
- The `tmux` stub responds to `show-option -gqv @useful-foo-bar` by reading `$MOCK_OPT_useful_foo_bar` (strip `@`, replace `-` with `_`).
- Each test gets a fresh `TMUX_USEFUL_CACHE_DIR` via `mktemp -d` so caches never leak between cases.
- Run all tests: `make test` (or `bats tests/*.bats`).

## Things to avoid

- **Don't add background-color blocks** to scripts or the default config. The plugin's identity is foreground-only color; PRs that re-introduce powerline-style chrome will be rejected.
- **Don't shell out per-segment more than once per refresh.** If you need multiple values from the same source, compute them in one script.
- **Don't break the silent-when-healthy contract.** A new segment that prints "OK" all day defeats the bar's whole point.
- **Don't hard-code colors.** Use `color_ok` / `color_warn` / `color_crit` / `color_accent` / `color_dim` from `helpers.sh` so users can override via `@useful-color-*`.
- **Don't write outside the cache dir.** No state in `~/.config`, `$HOME`, etc. — `TMUX_USEFUL_CACHE_DIR` (default `/tmp`) is the only writable location.
- **Don't introduce Linux-specific commands silently.** This is a macOS plugin today. Cross-platform support is a future feature; if you add it, gate it behind `uname -s` checks and add Linux stubs + tests.

## Common pitfalls

- `tmux` percent-format expansion (`%H`, `%S`, etc.) runs on the format string, **not** on `#(...)` script output. So scripts can emit literal `%` freely. The user's tmux.conf still needs `%%` to get a literal `%` inside a format string.
- `memory_pressure` reports *free* percentage; we compute used = 100 − free.
- `pmset -g batt` line-2 includes the percent as `<digits>%;` — match `[0-9]{1,3}%` not just `[0-9]+%`.
- `wttr.in` returns plain text like `location not found: location not found` for invalid locations. The success regex must explicitly filter these strings; an empty-check alone is not enough.
- The `#[fg=default]` reset is mandatory at the end of any colored run — without it, color bleeds into whatever segment comes next.

## When in doubt

Read `README.md` (user contract) and the existing test files (executable spec). If a behavior isn't in either, it isn't a guaranteed contract — feel free to change it, but add a test alongside the change.
