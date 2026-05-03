# Changelog

All notable user-visible changes are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/) starting at v0.1.0.

## [Unreleased]

### Added

- **`#{useful_pane}` segment** — active-pane command indicator (vim, claude,
  ssh, …) modeled on lualine's filename section. Hidden for default shells
  and pure-version-number commands. Adds situational awareness about what
  you're focused on, addressing the "active-buffer indicator" pattern from
  best-in-class TUI apps (Neovim/lualine, Claude Code's mode line).
- **Theme presets** via `@useful-theme`: `nord` *(default)*, `catppuccin`,
  `gruvbox`, `everforest`, `vitesse`, `rose-pine`. All dim tones pass WCAG
  AA contrast against typical dark terminal backgrounds. Individual
  `@useful-color-*` overrides still win over the theme.
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

[Unreleased]: https://github.com/ziweiwu/tmux-useful-status-line/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/ziweiwu/tmux-useful-status-line/releases/tag/v0.1.0
