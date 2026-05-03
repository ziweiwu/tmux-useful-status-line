# tmux-useful-status-line

**A tmux status line that's quiet when your machine is fine and loud when it isn't.**

Most status-line plugins shout about every metric all the time — CPU, RAM, disk, battery, weather — each in its own colored block, all competing for attention. Nothing pops because everything pops. This plugin inverts that: routine values stay hidden, color is reserved for state changes, and the bar is calm 95% of the time.

Six segments, each silent until they have something to say.

| Placeholder | Output |
|---|---|
| `#{useful_system}`   | CPU bar / mem% / disk%. Hidden when healthy by default; warn yellow, crit red. |
| `#{useful_battery}`  | Glyph + percent. Color tracks state; charging glyph is distinct. |
| `#{useful_weather}`  | `☁ 7°C` from wttr.in (or verbose with humidity/wind). Dim by default. |
| `#{useful_spotify}`  | Now-playing track. Empty when not playing. Long titles slide once on track change. |
| `#{useful_git}`      | Branch + dirty mark. Empty outside a repo. Warn-color when working tree is dirty. |
| `#{useful_pane}`     | Active pane's command (vim, claude, ssh, …). Hidden for default shells. |

## Install

```tmux
# In ~/.tmux.conf:
set -g @plugin 'ziweiwu/tmux-useful-status-line'
set -g @useful-default-layout on
```

Then `prefix + I` (with [TPM](https://github.com/tmux-plugins/tpm) installed) — you're done.

> **Need a Nerd Font?** Some default glyphs need one. `brew install --cask font-hack-nerd-font`, or set ASCII fallbacks (see [No Nerd Font?](#no-nerd-font)).

### Manual install (no TPM)

```sh
git clone https://github.com/ziweiwu/tmux-useful-status-line ~/.tmux/plugins/tmux-useful-status-line
```

```tmux
run-shell ~/.tmux/plugins/tmux-useful-status-line/useful-status-line.tmux
set -g @useful-default-layout on
```

## Requirements

- tmux 3.0+
- macOS or Linux (system + battery work on both; spotify is macOS-only)
- `curl` for the weather segment (skip otherwise)

## Custom layout

If you'd rather hand-author the bar, skip `@useful-default-layout` and write your own:

```tmux
set -g status-interval 30
set -g status-right-length 200
set -g status-right "#{useful_spotify}#{useful_git}#{useful_system}#{useful_weather}#{useful_battery} #[fg=#88c0d0]%H:%M #[default]"
```

> Each segment self-pads with one leading space and emits no trailing space. Don't add your own spaces between `#{useful_*}` placeholders — they'll double up.

To disable a segment without editing your `status-right`:

```tmux
set -g @useful-spotify-enabled  off    # also: -system, -weather, -battery, -git, -pane
```

## Configuration

All options are `set -g @useful-...`. Defaults shown.

### Themes

```tmux
set -g @useful-theme "nord"
```

Available: `nord` *(default)*, `catppuccin-mocha`/`-macchiato`/`-frappe`/`-latte`, `gruvbox`/`-light`, `everforest`, `vitesse`, `rose-pine`/`-dawn`, `tokyo-night`, `dracula`, `solarized-dark`/`-light`, `onedark`. All dim tones pass WCAG AA contrast.

Auto light/dark (Ghostty-style):

```tmux
set -g @useful-theme "dark:catppuccin-mocha,light:catppuccin-latte"
```

Override individual colors (wins over the theme):

```tmux
set -g @useful-color-ok     "#a3be8c"   # also -warn / -crit / -accent / -dim
```

### System (CPU, mem, disk)

```tmux
set -g @useful-system-show-when "warn-and-crit"   # warn-and-crit | mem-and-disk-always | all-always
set -g @useful-cpu-style        "text"            # text ("cpu 70%") | bar ("███▌░░░░░░")
set -g @useful-load-warn 70                       # % of (load1 ÷ ncpu)
set -g @useful-load-crit 100
set -g @useful-mem-warn  75
set -g @useful-mem-crit  90
set -g @useful-disk-warn 80
set -g @useful-disk-crit 95
set -g @useful-load-crit-prefix "!"               # set to "none" to suppress
set -g @useful-mem-crit-prefix  "!"               # ditto
set -g @useful-disk-crit-prefix "!"
```

### Battery

```tmux
set -g @useful-batt-warn       40       # below: warn color (when discharging)
set -g @useful-batt-crit       20       # below: crit color + "!" prefix
set -g @useful-batt-show-when  "always" # always | discharging-or-low | low-only
set -g @useful-batt-icons-ascii off     # "on" → [####] etc., for non-Nerd-Font terminals
```

### Spotify

```tmux
set -g @useful-spotify-max-len   30
set -g @useful-spotify-separator " · "
set -g @useful-spotify-scroll    "on"   # slides through long titles once on track change
```

`REDUCED_MOTION=1` or `TMUX_USEFUL_REDUCED_MOTION=1` in your env forces scroll off.

### Weather

```tmux
set -g @useful-weather-location ""       # "" = wttr.in geo-IP. e.g. "Toronto", "London,UK", "94103"
set -g @useful-weather-format   "%c+%t"  # condition + temp. Verbose: "%c+%C+%t++💧%h++💨%w"
```

### Git

```tmux
set -g @useful-git-skip-untracked "off"  # "on" speeds up dirty check in monorepos
set -g @useful-git-dirty-mark     "*"
```

### Pane

```tmux
set -g @useful-pane-hide "zsh bash sh fish dash tmux"   # commands to suppress (boring shells)
```

### Cache directory

Defaults to `${TMPDIR:-/tmp}/tmux-useful-<UID>-<socket-hash>` so multiple servers/users don't collide. Override with `@useful-cache-dir`.

## No Nerd Font?

```tmux
set -g @useful-icon-load        "cpu"      # default; was Nerd Font  before
set -g @useful-icon-mem         "mem"
set -g @useful-icon-disk        "disk"
set -g @useful-batt-icons-ascii "on"       # battery as [####] 92%
set -g @useful-spotify-icon     "♪"
set -g @useful-git-icon         "git"
```

## Troubleshooting

| Symptom | Cause |
|---|---|
| Bar didn't change after install | `status-right` doesn't reference any `#{useful_*}`. Set `@useful-default-layout on` or use the Custom layout snippet. |
| Tofu boxes (□) | Missing Nerd Font — see above. |
| Weather empty | Network down + no cached value, or `@useful-weather-enabled off`. |
| Weather has `~` prefix | Cached data older than 1hr (network probably down). |
| Window shows `0:2.1.119` instead of `0:claude` | OSC title from the running program. Add `setw -g allow-rename off`. |
| Spotify never appears | Spotify not running or paused — empty by design. |

## Uninstall

The plugin mutates `status-left`/`status-right` in place. Removing `@plugin` doesn't revert the running server. Either restart (`tmux kill-server`) or:

```sh
tmux set -gu status-right; tmux set -gu status-left; tmux source-file ~/.tmux.conf
```

## Development

```sh
make check    # shellcheck + 120 bats tests
```

CI runs the matrix on macOS + Ubuntu for every push. See [AGENTS.md](AGENTS.md) for the conventions.

## License

MIT
