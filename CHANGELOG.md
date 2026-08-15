# Changelog

All notable user-visible changes are documented here. The format is based on
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and this project
follows [Semantic Versioning](https://semver.org/) starting at v0.1.0.

## [Unreleased]

## [0.3.0] — 2026-08-15

### Added

- **`@useful-timeout`** (default 3s) — a wall-clock budget for every external
  data source. `df` on a stale NFS mount, `git status` on a network
  filesystem, and `osascript` against a wedged Spotify can all block forever;
  because the driver runs the six segments serially in one process, one stuck
  call froze the entire status line, and the shell-prompt recipe with it. Uses
  `timeout(1)` where the platform ships one and a bash watchdog where it does
  not.
- **`@useful-timeout-total`** (default 10s) — a ceiling on the whole refresh.
  The per-call limit bounded each source but not their sum: `system` guards
  four external calls, `git` three, `spotify` two, `battery` one, so a host
  where everything is wedged at once could still block `10 x @useful-timeout`
  with every individual call honouring its limit.
- **`@useful-contrast aa`** — opt-in WCAG AA corrections for the bundled
  themes. The palettes are reproduced from upstream byte for byte, which left
  24 of 80 tones below the 4.5:1 threshold against their own canonical
  background (nord's crit at 3.05:1, rose-pine-dawn's warn at 2.05:1 — less
  visible than the same theme's "healthy" green). The corrected set moves
  lightness only, so each tone still reads as the theme's colour.
  `tests/test_themes.bats` measures every tone of every theme.
- **`@useful-batt-crit-prefix`** (default `"!"`) — parity with the per-metric
  crit prefixes `system` already exposed. A user who wanted colour-only crit
  signalling could not get it for battery.
- **`@useful-weather-max-len`** (default 24 cells) — weather was the one
  segment that never truncated, so a wttr.in error page or captive-portal
  interception landed in the bar verbatim.
- **Icons can be turned off** — set any icon option to `none` / `off`.
  `""` never worked: tmux options treat an empty value as unset, so it fell
  back to the default glyph.

### Fixed

- **Invalid UTF-8 defeated the cell-width accounting.** The decoder trusted any
  byte ≥ 0xC0 as a multi-byte lead, so one bad byte swallowed up to three
  following ASCII characters. A string measured 29 cells and rendered 33
  columns — overflowing the exact budget `useful_truncate` exists to
  guarantee. Invalid lead bytes, non-continuation follow bytes and truncated
  tails now each count as one cell, matching what terminals actually draw.
- **A cell budget was not a bound on length.** Combining marks measure zero
  cells, so 500 stacked diacritics measured *one* cell and passed through
  untouched — 501 characters into a bar promised 5. Zero-width runs are now
  clamped at 4 per base glyph, which no real script exceeds.
- **Untrusted text was injected into the status line as tmux markup.** Git
  branch names, Spotify track titles and wttr.in responses all reach a tmux
  format string, where `#` is live syntax; a track title containing
  `#[bg=red]` could repaint the bar. All three are now escaped, and the
  ansi/plain/json renderers decode the escape.
- **A cache file dated in the future never expired.** The freshness test
  compared a negative age against the TTL and always won, pinning the value
  until real time caught up. Clock skew and snapshot-restored VMs produce this.
- **Offline weather re-attempted a blocking fetch on every refresh.** A failed
  fetch wrote nothing, so the refresh check never saw an attempt. Failures are
  now rate-limited to one a minute, like successes are to one per
  `@useful-weather-refresh`.
- **A typo'd numeric option silently deleted its segment.** `@useful-mem-warn
  "seventy"` reached `[ x -ge y ]` raw; bash wrote "integer expression
  expected" to a stderr tmux discards, and the segment just vanished. Numeric
  options are validated and fall back to their documented default, with one
  diagnostic line on stderr.
- **Garbled data sources were read as real measurements.** An unparseable
  `memory_pressure` reading inverted into a *100%-used critical* on every
  refresh; a negative load average spliced the whole glyph table into the CPU
  bar (`${glyphs:-5:1}` is the default-value operator, not a slice).
- **A data source that ignored SIGTERM defeated the timeout entirely.** The
  watchdog signalled once and then waited, so a child that trapped TERM —
  routine for wrapper scripts and anything with a graceful-shutdown handler —
  hung the driver forever *and* leaked as an orphan, which is precisely the
  failure the timeout was added to prevent. It now escalates to SIGKILL after a
  one-second grace period. `useful_timeout` also no longer delegates to
  `timeout(1)` when the platform has one: that dual-path design disagreed with
  itself twice (about `0`, and about SIGKILL escalation), and macOS ships no
  `timeout(1)` anyway, so the fallback was already the main path.
- **A raised `-max-len` could freeze the status line for minutes.** bash's
  `${var//pat/rep}` is quadratic in the number of matches (measured: 2k matches
  0.6s, 4k 4.3s, 8k 38s) and `useful_escape` doubles every `#`, so a hash-dense
  wttr.in body against a large budget never finished. Cell budgets are now
  capped at 512 — wider than any terminal — and `useful_truncate` asks the
  window for its verdict instead of measuring the whole string first, making
  truncation cost track the budget rather than the input length.
- **Control characters reached the status line unescaped.** A newline in a
  wttr.in body broke the single-line contract; a carriage return let untrusted
  text overprint the segment's own output, hiding the `~` stale marker or
  forging a truncation ellipsis; and either produced JSON that RFC 8259 forbids,
  so a strict waybar-side parser rejected the whole object. `useful_escape` now
  replaces C0 controls with a space, and `useful_json_escape` handles `\r` and
  any remaining control byte.
- **Overlong encodings, UTF-16 surrogates and codepoints past U+10FFFF decoded
  as valid**, each counting one cell where a compliant terminal draws one
  replacement glyph per byte — 24 overlong sequences measured 24 cells and
  rendered 72 columns. The first continuation byte is now range-checked per
  lead byte, per RFC 3629.
- **Cache entries were trusted without validation.** A `tee` killed mid-write
  left a colour run open, and tmux bled that colour through every later segment
  for the whole TTL; a corrupted file put raw bytes straight into the terminal.
  Entries are now stripped of control characters, closed with a reset if they
  opened a colour run, and rejected outright when implausibly long.
- **Warn was distinguishable from healthy by colour alone** wherever a segment
  renders healthy values — `@useful-system-show-when all-always` /
  `mem-and-disk-always`, and battery's default `always` mode. Warn now takes a
  `~` marker in those modes, so the ladder is `""` / `~` / `!`. Crit remains
  `!` in every segment and every mode: a status line is read as one line, and a
  doubled marker on one segment beside a single one on another would claim the
  first was worse when both are critical — false to precisely the readers who
  have nothing but the prefix to go on. The default `warn-and-crit` system mode
  is unchanged.
- **A wedged segment silenced the healthy segments after it.** The whole-run
  budget cancelled any call made after the clock ran out, and the driver runs
  segments in a fixed order — so a stuck `git` blanked a working `battery`, and
  the bar went empty for a reason that had nothing to do with the segment that
  vanished. The budget now shrinks later calls to a one-second floor instead of
  refusing them, which costs nothing for a healthy source and still bounds the
  overrun.
- **A run of zero-width marks escaped the cell budget's early exit.** The budget
  counter only advances for glyphs that occupy cells, so a title of stacked
  combining marks walked the whole input however small the budget was — seconds
  of pure-bash CPU on stock defaults, where neither timeout can reach it. The
  scan is now bounded by the codepoints a budget could legitimately consume,
  and the input is cut to match before the loop starts.
- **The mark clamp was mistaken for a truncation.** Both set the same flag, and
  that flag decides whether an ellipsis is owed — so a branch name that fitted
  comfortably still got a "…", and at an exact fit a real character was dropped
  to make room for it. The clamp now reports itself separately.
- **An empty icon left a doubled space** in every segment's output.
- The `dim`-tones-pass-WCAG-AA claim in `scripts/themes.sh` and the README was
  false for 6 of 16 themes. Corrected, and now enforced by a test.
- `tests/test_helpers.bash` no longer inherits `COLORFGBG`/`NO_COLOR` from the
  developer's shell, which made the theme auto-detection test fail on any
  machine whose terminal sets them.

Known limitation, recorded deliberately: bounding the width scan means content
positioned *after* an oversized run of zero-width marks is elided rather than
rendered — `"a"` + 100,000 combining marks + `"bbb"` yields the `a` and its
first four marks, without the `bbb`. Skipping a mark run cheaply is not
something bash 3.2 can do, and no real text carries thousands of stacked marks,
so the alternative is a status line a hostile track title can freeze.
`useful_window` reports it as `USEFUL_WINDOW_SCAN_LIMITED`, distinct from an
ordinary budget overflow.

### Changed

- `useful-status --help` leads with examples, per clig.dev.
- `tests/stubs/tmux` resolves option names with parameter expansion instead of
  `printf | tr | tr`, which was costing ~124 forks per config snapshot. The
  suite runs about 30% faster; no product code involved.
- Linux/BSD light-dark auto-detection and its `COLORFGBG` caveats are now
  documented, at parity with the macOS half.

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

[Unreleased]: https://github.com/ziweiwu/tmux-useful-status-line/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/ziweiwu/tmux-useful-status-line/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/ziweiwu/tmux-useful-status-line/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/ziweiwu/tmux-useful-status-line/releases/tag/v0.1.0
