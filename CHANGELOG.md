# Changelog

All notable user-visible changes are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/) starting at v0.1.0.

## [Unreleased]

## [0.2.0] — 2026-08-09

### Added

- **`bin/useful-status` — a single-process driver** and a `#{useful_all}`
  placeholder that maps to it. Renders every segment from one bash process and
  one tmux round-trip instead of six `#()` shell-outs, with byte-identical
  output. Measured on macOS, warm cache, four segments: 31 tmux subprocesses
  and ~245 ms CPU per refresh before, 1 subprocess and ~115 ms after. The
  per-segment placeholders are unchanged and still supported.
- **Rendering for hosts that aren't tmux**: `--render=ansi|plain|json`
  translates the internal tmux markup into SGR escapes, bare text, or a
  waybar/i3blocks JSON object. JSON reports a severity per segment plus a
  worst-of `class`, so bars can style by state. Enables use from a shell
  prompt, starship, waybar, sketchybar, or plain `watch`.
- `@useful-render` and `@useful-segments` options, and `--render`,
  `--segments`, `--separator`, `--list` flags on the driver.

### Fixed

- **The disk segment never fired on macOS.** It read `df`'s Capacity column
  for `/`, which on APFS describes the sealed read-only *system snapshot* —
  12 GiB of a 926 GiB disk, reported as 2%, and effectively frozen. A 31%-full
  disk read as 2%, so `@useful-disk-warn` could never trigger. Darwin now
  computes total-minus-available; Linux keeps `Use%`, which is meaningful there.
- **Layout budgets are now measured in terminal cells, not characters.**
  `@useful-git-max-branch-len`, `@useful-pane-max-len` and
  `@useful-spotify-max-len` counted characters, so a 24-character CJK branch
  name (40 cells) passed the check untouched and pushed the rest of the bar off
  screen. Emoji in the weather format compounded it. For ASCII the behaviour is
  unchanged; for wide text the budget is now honoured.
- **The Spotify slide traversed character overflow, not cell overflow.** A
  Japanese title of 31 characters / 53 cells overflowed a 30-cell budget by one
  character, so the animation nudged a single glyph while the bar ran 23 cells
  over. It now slides across the real overflow and stays inside the budget.

- Two defects in the new width layer: a `U+FE0F` at the start of a string
  promoted a glyph that was not there (one cell too wide), and a budget too
  small to hold the ellipsis emitted it anyway, overflowing by a cell.

### Added

- `@useful-warn-prefix` (default empty) puts a non-colour marker on warnings,
  mirroring the existing `!` on criticals. It matters under
  `@useful-system-show-when all-always`, where healthy values render too and
  hue is otherwise the only thing separating warn from healthy. The default is
  empty so the stock look is unchanged.

### Changed

- **Config is fetched in one tmux call instead of one per option.** All ~57
  `@useful-*` options are expanded in a single `display-message -p` format
  string and snapshotted per process. Options are read once per script run
  rather than live per lookup — an invisible change in practice, since a run
  lasts milliseconds. Options not in the manifest still resolve via a
  per-option read, and a tmux that will not answer falls back to the old
  path, so behaviour is unchanged when a server is detached.
- The batched config now verifies that tmux actually expands
  `#{@user-option}` instead of assuming a minimum version. A tmux that echoes
  the token back verbatim (which would have put the literal string
  `#{@useful-mem-crit}` into a numeric comparison) or expands it to nothing
  (which would have silently ignored every setting) is detected, and lookups
  fall back to per-option reads. The check is free when any `@useful-*` option
  is set, and costs one extra call when none are.
- The auto light/dark appearance cache moved from `$TMPDIR/tmux-useful-appearance`
  into the per-UID cache directory. On Linux hosts with a shared `/tmp`, the
  first user to write that file owned it and every other user's write failed
  silently, making them re-probe the system appearance on every refresh.
- `git` and `pane` no longer spend their own `tmux display -p` call on pane
  context; it rides along in the config snapshot.
- `bin/useful-status` gained CLI manners: it renders plain when stdout is not a
  terminal or `NO_COLOR` is set, and grew `--version` / `-V`. Inside tmux it
  still emits tmux markup, because tmux captures `#()` through a pipe and a
  naive isatty check would break the status line.

- **`#{useful_pane}` segment** — active-pane command indicator (vim, claude,
  ssh, …) modeled on lualine's filename section. Hidden for default shells
  and pure-version-number commands. Adds situational awareness about what
  you're focused on, addressing the "active-buffer indicator" pattern from
  best-in-class TUI apps (Neovim/lualine, Claude Code's mode line).
- **Theme presets** via `@useful-theme`. Now ships **15 variants** across
  9 theme families, including the full Catppuccin family (Mocha/Macchiato/
  Frappe/Latte), Gruvbox light+dark, Rose Pine + Dawn, Tokyo Night,
  Dracula, Solarized light+dark, and One Dark. All dim tones pass WCAG AA
  contrast against the canonical background for each variant.
- **Auto light/dark switching** (Ghostty-style): `@useful-theme
  "dark:catppuccin-mocha,light:catppuccin-latte"` resolves to the dark or
  light half based on the system appearance. Detection is `defaults read`
  on macOS, `$COLORFGBG` heuristic on Linux. Cached for 60s.
- **Linux support** for `system` and `battery` segments. macOS-specific data
  sources (`sysctl`, `memory_pressure`, `pmset`) are still used on Darwin;
  Linux uses `/proc/loadavg`, `nproc`/`/proc/cpuinfo`, `free`, and
  `/sys/class/power_supply/BAT*/{capacity,status}`. The `spotify` segment
  remains macOS-only and exits cleanly on Linux.
- `@useful-git-skip-untracked on` option for monorepos — skips the untracked-
  file scan in `git status` (which can take seconds on large repos), trading
  accuracy for speed.
- GitHub Actions CI now runs the test matrix on both `macos-latest` and
  `ubuntu-latest`. 98 bats tests across both.
- Issue templates (`bug_report.md`, `feature_request.md`) and PR template
  under `.github/`.

## [0.1.0] — 2026-05-02

First tagged release. Eight rounds of UX/security/correctness review.

### Added

- Five status-line segments with `#{useful_*}` placeholders: `spotify`,
  `system`, `weather`, `battery`, `git`.
- Sliding-window animation for long Spotify titles on track change. Honors
  `REDUCED_MOTION` and `TMUX_USEFUL_REDUCED_MOTION` env vars.
- `@useful-default-layout on` opt-in for first-run users.
- Per-segment kill switches: `@useful-<segment>-enabled off`.
- Per-server cache namespacing under `${TMPDIR:-/tmp}/tmux-useful-<UID>-<socket-hash>`.
- ASCII-icon fallback toggle: `@useful-batt-icons-ascii on` plus per-icon
  overrides for users without a Nerd Font.
- `@useful-system-show-when` mode: `warn-and-crit` (default), `mem-and-disk-always`,
  or `all-always`.
- `!` prefix on critical warnings (color-blind-friendly state encoding).
- `~` prefix on stale weather data (replaces the original italic signal).
- AppleScript injection hardening: separator now passed as data, not interpolated.
- Cross-platform `file_mtime()` helper (BSD `stat -f %m` with GNU `stat -c %Y` fallback).
- Linux guard on macOS-only segments — they exit cleanly instead of producing
  bogus warnings.
- 88 bats unit tests, CI on macOS for every push and PR.

### Notes for early adopters

- `@useful-color-dim` default raised from `#4c566a` (WCAG fail) to `#7b8696`
  (WCAG AA pass).
- The plugin mutates `status-left`/`status-right` in-place. Removing the
  `@plugin` line does not revert the running tmux server. See `Uninstalling`
  in the README.
- Shipping as `0.x` (pre-1.0). Option names and default values may change
  in `0.x` releases — pin to a tag if you want stability.

[Unreleased]: https://github.com/ziweiwu/tmux-useful-status-line/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/ziweiwu/tmux-useful-status-line/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ziweiwu/tmux-useful-status-line/releases/tag/v0.1.0
