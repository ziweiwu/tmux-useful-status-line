# tmux-useful-status-line

A tmux status-line plugin that prioritizes **state over decoration**:

- **System health** (CPU load, memory, disk) is silent when fine, warns in yellow above thresholds, screams in red when critical.
- **Battery** changes color and glyph based on charge level and AC state.
- **Spotify** shows the current track only when something is playing.
- **Weather** caches aggressively and dims when the data goes stale.

Designed for macOS. Cheap on CPU — every script caches its output and most are no-ops most of the time.

## Preview

```
[ session  ~/path ]   1:zsh   2:vim*   ...                          Artist · Track    52%   ⛅ Light rain 4°C   100%  18:42
                                                          ^^^^^ shown only when relevant ^^^^^
```

When everything is healthy, the right side is just: weather, battery, time. When something is off, only the unhealthy metric pops in.

## Requirements

- tmux 3.0+
- macOS (uses `pmset`, `osascript`, `memory_pressure`, `sysctl`)
- A Nerd Font for the default glyphs (battery, disk). You can override icons via options if you don't use one.
- `curl` for weather (optional).

## Install via [TPM](https://github.com/tmux-plugins/tpm)

Add to `~/.tmux.conf`:

```tmux
set -g @plugin 'ziweiwu/tmux-useful-status-line'
```

Then press `prefix + I` to fetch the plugin.

## Manual install

```sh
git clone https://github.com/ziweiwu/tmux-useful-status-line ~/.tmux/plugins/tmux-useful-status-line
```

And add to `~/.tmux.conf`:

```tmux
run-shell ~/.tmux/plugins/tmux-useful-status-line/useful-status-line.tmux
```

## Usage

The plugin exposes four placeholders you can drop into `status-left` or `status-right`:

| Placeholder | Output |
|---|---|
| `#{useful_system}` | Load / mem / disk warnings (empty when healthy) |
| `#{useful_battery}` | Battery glyph + percent, colored by state |
| `#{useful_weather}` | Current weather from wttr.in (cached) |
| `#{useful_spotify}` | Spotify now-playing (empty when not playing) |

A reasonable starting point:

```tmux
set -g status-interval 30
set -g status-right-length 200
set -g status-right "#{useful_spotify} #{useful_system}#{useful_weather}  #{useful_battery}  #[fg=#88c0d0,bold]%H:%M #[default]"
```

## Configuration

All options are read via `set -g @useful-...` in `~/.tmux.conf`. Defaults shown.

### Weather

```tmux
set -g @useful-weather-location ""              # "" = wttr.in geo-IP guess. Otherwise: "Toronto", "London,UK", "94103"
set -g @useful-weather-format   "%c+%t"         # wttr.in format string. Default = condition icon + temperature.
set -g @useful-weather-refresh  900             # seconds between fetches
set -g @useful-weather-stale    3600            # dim cached output once it's older than this
```

The default format renders as `☁ 7°C` — the bare minimum your eye actually parses at a glance. For verbose mode with humidity and wind, override:

```tmux
set -g @useful-weather-format "%c+%C+%t++💧%h++💨%w"   # ☁ Overcast 7°C 💧81% 💨5km/h
```

### System health thresholds

`load-warn` / `load-crit` are expressed as percent of (load1 ÷ ncpu). Memory and disk are absolute percent.

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
set -g @useful-batt-warn 40                          # under this %, color turns warn (when not charging)
set -g @useful-batt-crit 20                          # under this %, color turns crit
set -g @useful-batt-show-when "always"               # always | discharging-or-low | low-only
set -g @useful-batt-full-pct 95                      # %≥this AND charging is treated as "full" and hidden
```

`@useful-batt-show-when` modes:
- `always` *(default)* — show the segment in all states. The charging glyph (󰂄) clearly distinguishes plugged-in from discharging.
- `discharging-or-low` — hide when fully charged and on AC; the most boring state your laptop can be in.
- `low-only` — hide unless the battery is below `batt-warn` *and* not charging.

### Spotify

```tmux
set -g @useful-spotify-max-len          30
set -g @useful-spotify-icon             ""
set -g @useful-spotify-separator        " · "
set -g @useful-spotify-scroll           "on"   # slide through long titles on track change
set -g @useful-spotify-scroll-dwell     2      # seconds dwelling at start and end
set -g @useful-spotify-scroll-duration  8      # seconds the slide itself takes
```

When the title is longer than `max-len` and `scroll` is on, the segment slides through the full text **once** when the track changes — 2s dwell at start, 8s slow slide, 2s dwell at end, then settles back to a truncated start view. The same track is never re-scrolled, so the bar is calm 99% of the time. This matches the "scroll on event, not on schedule" pattern that macOS Now Playing and iOS lock-screen players use.

To disable entirely: `set -g @useful-spotify-scroll off`.

### Colors

Override the four state colors. Defaults are Nord-ish but work on most palettes.

```tmux
set -g @useful-color-ok     "#a3be8c"
set -g @useful-color-warn   "#ebcb8b"
set -g @useful-color-crit   "#bf616a"
set -g @useful-color-accent "#b48ead"
set -g @useful-color-dim    "#4c566a"
```

### Icons

Override Nerd Font glyphs if you don't have one installed:

```tmux
set -g @useful-icon-load ""    # default 
set -g @useful-icon-mem  "MEM"  # default 
set -g @useful-icon-disk "DISK" # default 󰋊
```

## Development

```sh
make lint    # shellcheck on every script
make test    # run the bats test suite
make check   # both
```

The plugin ships with **45 unit tests** covering threshold logic, cache behavior, location-namespacing, glyph progression, formatter interpolation, and option overrides. CI runs them on macOS for every push and PR (`.github/workflows/ci.yml`).

If you're an LLM coding agent working on this repo, see [`AGENTS.md`](AGENTS.md) for conventions and pitfalls.

## Why use this?

A typical tmux status line looks like a cockpit: every metric on screen, all the time, in its own colored block. The problem is that **every block competes for attention with the same visual weight**, so nothing actually pops when something needs your attention.

This plugin inverts that. Routine numbers are hidden. Color is reserved for state, not identity. The bar is calm 95% of the time and lights up the moment the machine — or your music — needs your attention.

## License

MIT
