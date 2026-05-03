# tmux-useful-status-line

A tmux status-line plugin that prioritizes **state over decoration**. Routine values stay hidden; color is reserved for state changes; the bar pops only when something needs attention.

## Why use this?

A typical tmux status line looks like a cockpit: every metric on screen, all the time, in its own colored block. The problem is that *every block competes for attention with the same visual weight*, so nothing actually pops when something needs your attention. Stacking `tmux-cpu` + `tmux-battery` + `tmux-online` produces this exact failure mode.

This plugin inverts it: routine numbers are hidden, color is reserved for state, and the bar is calm 95% of the time. Five segments are bundled, each implementing the same "silent when fine, loud when not" contract:

| Segment | Behavior |
|---|---|
| `#{useful_system}`  | Shows CPU load / mem / disk **only** when above your thresholds. Yellow at warn, red at crit, with a leading `!` so the state survives color-blindness. |
| `#{useful_battery}` | Glyph + percent, color tracks state; charging is unambiguous via a distinct glyph. |
| `#{useful_weather}` | Compact `☁ 7°C` from wttr.in, dim by default (it's metadata, not status). Stale data is prefixed `~`. |
| `#{useful_spotify}` | Now-playing track. Empty when not playing. Long titles slide *once* on track change (matches macOS Now Playing). |
| `#{useful_git}` | Current branch + dirty mark. Empty outside a repo. Warn-color when the working tree is dirty. |

## Quick start

```sh
# 1. If you don't have TPM (the tmux plugin manager) yet:
git clone https://github.com/tmux-plugins/tpm ~/.tmux/plugins/tpm

# 2. Add the following lines to ~/.tmux.conf (open the file in your editor;
#    using `echo >>` here would duplicate them on re-run):
#
#    set -g @plugin 'tmux-plugins/tpm'
#    set -g @plugin 'ziweiwu/tmux-useful-status-line'
#    set -g @useful-default-layout on
#    run '~/.tmux/plugins/tpm/tpm'

# 3. Reload tmux + fetch the plugin:
tmux source-file ~/.tmux.conf
# Press: prefix + I
```

That's it. With `@useful-default-layout on`, the plugin seeds a sensible `status-right` for you. To customize, leave that option off and write your own format string referencing the placeholders above.

> [!IMPORTANT]
> The default glyphs (battery icons, disk icon) need a [Nerd Font](https://www.nerdfonts.com/). If you see broken-tofu boxes (□) in your bar, see [No Nerd Font?](#no-nerd-font) below.

## Manual install (without TPM)

```sh
git clone https://github.com/ziweiwu/tmux-useful-status-line ~/.tmux/plugins/tmux-useful-status-line
```

Then in `~/.tmux.conf`:

```tmux
run-shell ~/.tmux/plugins/tmux-useful-status-line/useful-status-line.tmux
set -g @useful-default-layout on    # or write your own status-right
```

## Requirements

- tmux 3.0+
- **macOS or Linux**:
  - `system` segment uses `sysctl` + `memory_pressure` on macOS; `/proc/loadavg` + `free` + `nproc` on Linux.
  - `battery` uses `pmset` on macOS; `/sys/class/power_supply/BAT*/{capacity,status}` on Linux.
  - `spotify` is macOS-only (uses `osascript`); the segment exits cleanly on Linux.
- `curl` for the `weather` segment (skip if you don't use it).
- A Nerd Font for the default battery/disk glyphs — or use the ASCII-fallback toggle below.

## No Nerd Font?

The `system` and `battery` segments default to Nerd Font codepoints. Two ways to fix this if you don't have one:

```tmux
# Option A — install one (one-liner on macOS):
# brew install --cask font-hack-nerd-font

# Option B — use ASCII fallbacks in your config:
set -g @useful-icon-load        "LOAD"
set -g @useful-icon-mem         "MEM"
set -g @useful-icon-disk        "DISK"
set -g @useful-spotify-icon     "♪"
set -g @useful-batt-icons-ascii "on"
set -g @useful-git-icon         "git"
```

The ASCII battery toggle renders as `[####] 92%` etc. Less pretty, works on default macOS Terminal.app and any SSH session.

## Custom layout

If you'd rather hand-author the layout (and skip `@useful-default-layout on`):

```tmux
set -g status-interval 30      # 30s is enough for HH:MM and warning-band metrics
set -g status-right-length 200
set -g status-right "#{useful_spotify}#{useful_git}#{useful_system}#{useful_weather}#{useful_battery} #[fg=#88c0d0]%H:%M #[default]"
```

> [!NOTE]
> Each segment self-pads with a single leading space and emits no trailing space. **Don't add your own spaces between `#{useful_*}` placeholders** — they'll double up. Add spaces around fixed-text segments (clock, your custom text) only.

To disable a segment without editing your `status-right`:

```tmux
set -g @useful-spotify-enabled  off
set -g @useful-system-enabled   off
set -g @useful-weather-enabled  off
set -g @useful-battery-enabled  off
set -g @useful-git-enabled      off
```

## Configuration reference

All options are `set -g @useful-...` in `~/.tmux.conf`. Defaults shown.

### Weather

```tmux
set -g @useful-weather-location ""        # "" = wttr.in geo-IP. Otherwise: "Toronto", "London,UK", "94103"
set -g @useful-weather-format   "%c+%t"   # condition icon + temperature
set -g @useful-weather-refresh  900       # seconds between fetches
set -g @useful-weather-stale    3600      # prepend "~" to cached output older than this
```

For verbose mode with humidity + wind: `set -g @useful-weather-format "%c+%C+%t++💧%h++💨%w"`.

### System health thresholds

`load-*` are expressed as % of `load1 ÷ ncpu`. Memory and disk are absolute %.

```tmux
set -g @useful-load-warn 70
set -g @useful-load-crit 100
set -g @useful-mem-warn  75
set -g @useful-mem-crit  90
set -g @useful-disk-warn 80
set -g @useful-disk-crit 95
```

### Battery

```tmux
set -g @useful-batt-warn       40           # below this %, color turns warn (when not charging)
set -g @useful-batt-crit       20           # below this %, color turns crit + adds "!" prefix
set -g @useful-batt-show-when  "always"     # always | discharging-or-low | low-only
set -g @useful-batt-full-pct   95
set -g @useful-batt-icons-ascii off         # toggle to "on" for ASCII fallback glyphs
```

Individual icon overrides (skip these if you set `batt-icons-ascii on`):

```tmux
set -g @useful-batt-icon-charging "󰂄"
set -g @useful-batt-icon-full     "󰂂"
set -g @useful-batt-icon-high     "󰂀"
set -g @useful-batt-icon-mid      "󰁾"
set -g @useful-batt-icon-low      "󰁺"
set -g @useful-batt-icon-empty    "󰂃"
```

### Spotify

```tmux
set -g @useful-spotify-max-len         30
set -g @useful-spotify-icon            ""
set -g @useful-spotify-separator       " · "
set -g @useful-spotify-scroll          "on"
set -g @useful-spotify-scroll-dwell    2
set -g @useful-spotify-scroll-duration 8
```

When a title is longer than `max-len` and `scroll` is on, the segment slides through the full text **once** on each track change — 2s dwell at start, 8s slow slide, 2s dwell at end, then settles back to a truncated start view. The same track never re-scrolls.

To disable scrolling: `set -g @useful-spotify-scroll off`. To honor a global motion-sensitivity preference: set `REDUCED_MOTION=1` or `TMUX_USEFUL_REDUCED_MOTION=1` in your environment — both force scrolling off.

### Git

```tmux
set -g @useful-git-icon            ""
set -g @useful-git-dirty-mark      "*"
set -g @useful-git-max-branch-len  24
set -g @useful-git-skip-untracked  "off"   # speed up dirty check in monorepos
```

`@useful-git-skip-untracked on` skips the untracked-file scan in `git status`, which can be slow (seconds) in large repos. Trade-off: untracked files won't trigger the dirty mark, only staged/unstaged tracked changes will.

Empty outside a repo. Branch name in dim color when the working tree is clean; warn color with a `*` (or your custom `dirty-mark`) when something is uncommitted, unstaged, or untracked. Detached HEAD shows `@<short-sha>`.

### Themes

Pick a bundled palette in one line. Defaults to Nord. Individual color
overrides win over the theme preset.

```tmux
set -g @useful-theme "nord"           # nord | catppuccin | gruvbox | everforest | vitesse | rose-pine
```

| Theme | OK | Warn | Crit | Accent | Dim |
|---|---|---|---|---|---|
| `nord` *(default)* | `#a3be8c` | `#ebcb8b` | `#bf616a` | `#b48ead` | `#7b8696` |
| `catppuccin` (mocha) | `#a6e3a1` | `#f9e2af` | `#f38ba8` | `#cba6f7` | `#9399b2` |
| `gruvbox` (dark) | `#b8bb26` | `#fabd2f` | `#fb4934` | `#d3869b` | `#a89984` |
| `everforest` (dark) | `#a7c080` | `#dbbc7f` | `#e67e80` | `#d699b6` | `#9da9a0` |
| `vitesse` (dark) | `#4d9375` | `#d4976c` | `#cb7676` | `#a8b1ff` | `#8a8d96` |
| `rose-pine` | `#9ccfd8` | `#f6c177` | `#eb6f92` | `#c4a7e7` | `#908caa` |

All theme dim values pass WCAG AA contrast on a typical dark terminal background.

### Colors (per-token override)

Override individual tones — wins over `@useful-theme`.

```tmux
set -g @useful-color-ok     "#a3be8c"
set -g @useful-color-warn   "#ebcb8b"
set -g @useful-color-crit   "#bf616a"
set -g @useful-color-accent "#b48ead"
set -g @useful-color-dim    "#7b8696"
```

### Icons (system)

```tmux
set -g @useful-icon-load ""     # default Nerd Font glyph
set -g @useful-icon-mem  ""
set -g @useful-icon-disk "󰋊"
```

### Cache directory

Each script caches results to disk. By default the plugin uses `${TMPDIR:-/tmp}/tmux-useful-<UID>-<socket-hash>` so multiple servers, multiple users on a host, and multiple tmux sockets don't collide. Override:

```tmux
set -g @useful-cache-dir "/tmp/my-cache-dir"
```

## Troubleshooting

| Symptom | What's happening |
|---|---|
| The bar didn't change after install | `status-right` is empty or doesn't reference any `#{useful_*}` placeholder. Either set `@useful-default-layout on` or paste the [Custom layout](#custom-layout) example. |
| Boxes (□) where the battery icon should be | No Nerd Font installed. See [No Nerd Font?](#no-nerd-font). |
| Spotify never appears | (a) Spotify isn't running, or (b) it's paused. The segment is empty by design when nothing is playing. |
| Weather is empty | (a) `curl` fetch failed and there's no cached value yet, (b) you set an invalid location, or (c) `@useful-weather-enabled off` is set. |
| Weather has a `~` prefix | Cached data is older than `@useful-weather-stale` (default 1hr). Network is probably down. |
| `0:claude` shows the version (`0:2.1.119`) instead | tmux's `automatic-rename` is mirroring the program's terminal title. Add `setw -g automatic-rename-format "#{pane_current_command}"` to `~/.tmux.conf`. |

## Uninstalling

The plugin mutates `status-left`/`status-right` *in-place* by interpolating placeholders to `#(...)` shell-outs. Removing the `@plugin` line from your config is not enough on its own to revert the running tmux server. To fully clean up:

```sh
tmux kill-server         # nuclear option, simplest
# OR, manually:
tmux set -gu status-right
tmux set -gu status-left
# then reload your config to repopulate them from your conf
```

## Development

```sh
make lint    # shellcheck on every script
make test    # 79 bats unit tests
make check   # both
```

CI runs lint + tests on macOS for every push and PR. See [`AGENTS.md`](AGENTS.md) for conventions if you're an LLM coding agent.

## License

MIT
