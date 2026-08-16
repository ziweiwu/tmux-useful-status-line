# tmux-useful-status-line

**A tmux status line that's quiet when your machine is fine and loud when it isn't.**

Most status-line plugins shout about every metric all the time — CPU, RAM, disk, battery, weather — each in its own colored block, all competing for attention. Nothing pops because everything pops. This plugin inverts that: routine values stay hidden, color is reserved for state changes, and the bar is calm 95% of the time.

![The status line in three states: healthy, warning, critical](assets/status-line.svg)

*Rendered from real segment output — `tools/make-screenshot.sh` runs the plugin against
the test fixtures and draws what it emits, so the picture can't drift from the code.
Icons shown are the Nerd-Font-free variants; defaults use Nerd Font glyphs.*

Six segments, each silent until they have something to say.

| Placeholder | Output |
|---|---|
| `#{useful_system}`   | CPU bar / mem% / disk%. Hidden when healthy by default; warn yellow, crit red. |
| `#{useful_battery}`  | Glyph + percent. Color tracks state; charging glyph is distinct. |
| `#{useful_weather}`  | `☁ 7°C` from wttr.in (or verbose with humidity/wind). Dim by default. |
| `#{useful_spotify}`  | Now-playing track. Empty when not playing. Long titles slide once on track change. |
| `#{useful_git}`      | Branch + dirty mark. Empty outside a repo. Warn-color when working tree is dirty. |
| `#{useful_pane}`     | Active pane's command (vim, claude, ssh, …). Hidden for default shells. |
| `#{useful_all}`      | All six at once, from a single process. Cheaper than listing them individually — see [One process instead of six](#one-process-instead-of-six). |

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

Configuration is read in a single tmux round-trip using `#{@user-option}`
format expansion. If your tmux is too old to expand those, the plugin detects
it at startup and falls back to reading each option individually — the same
settings, just a few more subprocesses per refresh. Nothing silently reverts
to defaults.

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

`#{useful_git}` works in `status-left` too — pairing it with `#{b:pane_current_path}` gives you
"where am I / what branch" in one anchor. See the recipe below.

## One process instead of six

Each `#{useful_*}` placeholder is a separate `#()` shell-out: six bash startups
per status refresh. `#{useful_all}` runs every segment inside one process off
one tmux round-trip instead, and renders identical output.

```tmux
set -g status-right "#{useful_all} #[fg=#88c0d0]%H:%M #[default]"
```

Measured on macOS with a warm cache, four segments, 20 refreshes, CPU time
(wall-clock is too noisy on a loaded machine to compare honestly):

| | tmux subprocesses per refresh | CPU per refresh |
|---|---|---|
| Six separate `#()` placeholders | 31 | ~245 ms |
| Same, batched config (v0.2) | 6 | ~185 ms |
| `#{useful_all}` | 1 | ~115 ms |

For a subset, or to put segments in different places, call the driver directly:

```tmux
set -g status-left  "#[fg=#88c0d0,bold] #S #(~/.tmux/plugins/tmux-useful-status-line/bin/useful-status --segments=git) #[default]"
set -g status-right "#(~/.tmux/plugins/tmux-useful-status-line/bin/useful-status --segments=pane,system,battery)"
```

Two `#()` calls still beat six. The per-segment placeholders remain supported
and unchanged.

## Outside tmux

The segments talk to tmux through exactly three seams — config, pane context,
and colour markup — and all three have non-tmux fallbacks. `bin/useful-status`
is the entry point:

```sh
bin/useful-status --render=ansi     # SGR escapes, for a shell prompt
bin/useful-status --render=plain    # no colour
bin/useful-status --render=json     # for waybar / i3blocks
bin/useful-status --list            # available segment names
bin/useful-status --version
```

It behaves like a CLI should: piping or redirecting drops colour automatically,
`NO_COLOR` is honoured, data goes to stdout and errors to stderr, and a bad
flag exits non-zero. An explicit `--render` always wins over both.

Outside tmux it defaults to `--render=ansi`. Config resolution degrades in one
step rather than all at once:

- **A tmux server is reachable** (even from a terminal that isn't attached to
  it): your `@useful-*` globals are read normally, so a prompt outside tmux and
  a status line inside it stay in sync.
- **No server is reachable**: every option falls back to its default, and the
  `pane` segment renders empty because there is no pane to report on. Nothing
  errors, and no tmux server is started just to answer the query.

Everything else works in both cases.

```sh
# zsh right-prompt, refreshed on each prompt draw
RPROMPT='$(~/.tmux/plugins/tmux-useful-status-line/bin/useful-status --render=ansi --segments=system,battery)'

# starship custom module
[custom.useful]
command = "~/.tmux/plugins/tmux-useful-status-line/bin/useful-status --render=ansi"
when = true
format = "$output"
```

JSON mode reports a severity per segment plus a worst-of `class`, so bar
consumers can style by state:

```json
{"text":"mem 95% disk 85%","class":"critical","segments":[
  {"name":"system","text":"mem 95% disk 85%","severity":"critical"}]}
```

```jsonc
// waybar config
"custom/useful": {
  "exec": "~/.tmux/plugins/tmux-useful-status-line/bin/useful-status --render=json",
  "return-type": "json",
  "interval": 5
}
```

There is no separate config file: tmux options are the only configuration
source, by design. On a host with no tmux at all you get the defaults, which
are chosen to be reasonable unattended. If you need non-default thresholds
there, keep a detached tmux server around (`tmux new-session -d`) with your
`@useful-*` options set — the driver will read them.

## Real-world example

The author's daily-driver config, tuned for running several coding agents in parallel.
Catppuccin Mocha, CPU as a per-core fill bar, thresholds raised because a build box
sitting at 90% CPU is normal, not news.

```tmux
set -g status-interval 30
set -g status-style "bg=#1e1e2e,fg=#cdd6f4"   # Catppuccin Mocha base
set -g status-left-length  80
set -g status-right-length 200

set -g @useful-theme "catppuccin-mocha"

# This machine is busy by design — warn only when load matches core count,
# crit at 1.5x. The stock 70/100 cried wolf during every build.
set -g @useful-system-show-when   "all-always"
set -g @useful-cpu-style          "bar"
set -g @useful-load-warn          100
set -g @useful-load-crit          150
set -g @useful-load-crit-prefix   "none"   # red bar is loud enough without "!"

set -g @useful-weather-format "%c+%C+%t++💧%h++💨%w"

# Left: session · cwd (~ at $HOME) · branch.
set -g status-left "#[fg=#74c7ec,bold] #S #[fg=#6c7086,nobold]│#[fg=default] #{?#{==:#{pane_current_path},#{HOME}},~,#{b:pane_current_path}}#{useful_git} "

# Right: modal cue, then situational, then health, then ambient, then clock.
set -g status-right "#{prefix_highlight}#{useful_pane}#{useful_spotify}#{useful_system}#{useful_weather}#{useful_battery} #[fg=#74c7ec]%H:%M #[fg=#6c7086]%Z #[default]"

# Window list: inactive dim, active sapphire, hairline separator.
setw -g allow-rename off                     # keep OSC titles out of the bar
setw -g automatic-rename-format      "#{pane_current_command}"
setw -g window-status-format         "#[fg=#6c7086] #I:#W#{?window_zoomed_flag,Z,}#{?window_bell_flag,#,} "
setw -g window-status-current-format "#[fg=#74c7ec,bold] #I:#W#{?window_zoomed_flag,Z,} #[default]"
setw -g window-status-separator      "#[fg=#313244]│"
```

Two tmux settings that pair well with `#{useful_pane}` when you keep agents in
background windows — the pane border says *what* each agent is doing, and the bell
flag lights up when a background one finishes:

```tmux
set -g pane-border-status top
set -g pane-border-format " #{?pane_active,#[fg=#74c7ec#,bold],#[fg=#6c7086]}#{pane_title} "
setw -g monitor-bell on
set  -g bell-action  other
set  -g visual-bell  off
```

## Configuration

All options are `set -g @useful-...`. Defaults shown.

### Themes

```tmux
set -g @useful-theme "nord"
```

Available: `nord` *(default)*, `catppuccin-mocha`/`-macchiato`/`-frappe`/`-latte`, `gruvbox`/`-light`, `everforest`, `vitesse`, `rose-pine`/`-dawn`, `tokyo-night`, `dracula`, `solarized-dark`/`-light`, `onedark`.

Each palette is reproduced from its upstream source, byte for byte. That
fidelity is the point of naming a theme after its author — and it also means
24 of the 80 tones sit below the WCAG AA 4.5:1 contrast threshold against
their own canonical background. Nord's aurora red measures 3.05:1;
rose-pine-dawn's warm orange measures 2.05:1, which is *less* visible than
that theme's "everything is fine" green.

To opt into corrected tones:

```tmux
set -g @useful-contrast "aa"
```

Every tone of every theme then clears 4.5:1, adjusted in lightness only so it
still reads as the theme's colour. `tests/test_themes.bats` measures this, so
the claim stays true. An explicit `@useful-color-*` outranks both.

Auto light/dark (Ghostty-style):

```tmux
set -g @useful-theme "dark:catppuccin-mocha,light:catppuccin-latte"
```

Appearance is detected per platform, cached for 60s:

| Platform | Signal | Caveat |
|---|---|---|
| macOS | `defaults read -g AppleInterfaceStyle` | Follows the system setting. |
| Everything else | the `COLORFGBG` environment variable | Best-effort. Only some terminals (rxvt, konsole, and imitators) set it; when it is absent the guess is `dark`. It is inherited from the process environment rather than queried live, so it can be stale after `tmux attach` from a different terminal. |

If auto mode picks the wrong half on Linux, name the theme directly.

Override individual colors (wins over the theme):

```tmux
set -g @useful-color-ok     "#a3be8c"   # also -warn / -crit / -accent / -dim
```

### System (CPU, mem, disk)

Severity is readable without colour. **Crit is always `!`**, in every segment
and every mode. Warn takes `~` wherever healthy values are also rendered — under
`all-always` or `mem-and-disk-always` — because there warn would otherwise
differ from healthy by hue alone. In the default `warn-and-crit` mode a healthy
metric renders nothing at all, so the segment appearing *is* the cue and warn
needs no prefix.

The two markers differ by shape rather than by count on purpose: a status line
is read as one line, so `!mem 95%` beside a doubled marker on another segment
would claim one is worse when both are critical — false to exactly the readers
who have nothing but the prefix. Override either with `@useful-warn-prefix` and
`@useful-<metric>-crit-prefix`; `none` on either suppresses it.

`~` means the same thing wherever it appears: **advisory, not alarm**. That is
also what it means on stale weather data, so a line can carry it twice —
`~Sunny 20C ~mem 80%` reads as "this reading may be old" and "this value is
elevated". Both are the same register, and neither is urgent; `!` is the only
marker that means "act now". `--render=json` reports the exact severity per
segment for consumers that need to tell them apart.

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

**Memory is the kernel's pressure figure, not Activity Monitor's.** `mem` comes
from `memory_pressure` on macOS, which counts inactive/reclaimable pages as
available. Activity Monitor's "Memory Used" (wired + active + compressed) reads
roughly 10 points higher for the same instant — 69% vs 80% on the machine this
was calibrated on. The pressure figure is the better "should I worry" signal,
but bear the offset in mind when picking `@useful-mem-warn`. Linux uses `free`'s
*available* column, which is the equivalent idea.

**Colour-blind legibility.** Critical values are prefixed with `!` by default so
red and yellow don't have to be told apart. Warnings have no prefix, because in
the default silent-when-healthy mode a warning segment *appearing* is itself the
cue. If you turn on an always-mode (below), healthy values render too and colour
becomes the only difference — set a warning prefix as well:

```tmux
set -g @useful-warn-prefix "~"     # default: "" (none)
```

### Battery

```tmux
set -g @useful-batt-warn       40       # below: warn color (when discharging)
set -g @useful-batt-crit       20       # below: crit color + crit prefix (see the ladder below)
set -g @useful-batt-show-when  "always" # always | discharging-or-low | low-only
set -g @useful-batt-icons-ascii off     # "on" → [####] etc., for non-Nerd-Font terminals
set -g @useful-batt-full-pct   95       # at or above: treated as full (full glyph)
set -g @useful-batt-crit-prefix "!"     # colour-free crit cue; "none" to suppress
```

Individual glyphs: `@useful-batt-icon-full` / `-high` / `-mid` / `-low` / `-empty` / `-charging`.
Set any of them to `none` to drop the glyph entirely.

The glyph is a **charge gauge**, with fixed tiers at 90/60/30/15%. It is
deliberately independent of `@useful-batt-warn` / `-crit`, which control
*severity*. That is exactly why the prefixes carry the severity: a warn battery
at 39% and a healthy one at 45% draw the *same* mid glyph. So the ladder is
`""` / `~` / `!`, matching the system segment. In `low-only` mode nothing
renders unless the battery is already low, so warn needs no marker there.

### Spotify

```tmux
set -g @useful-spotify-max-len   30      # capped at 512
set -g @useful-spotify-separator " · "
set -g @useful-spotify-scroll    "on"   # slides through long titles once on track change
set -g @useful-spotify-scroll-dwell    2   # seconds held at the start before sliding
set -g @useful-spotify-scroll-duration 8   # seconds the slide runs before settling
```

`REDUCED_MOTION=1` or `TMUX_USEFUL_REDUCED_MOTION=1` in your env forces scroll off.

### Weather

```tmux
set -g @useful-weather-location ""       # "" = wttr.in geo-IP. e.g. "Toronto", "London,UK", "94103"
set -g @useful-weather-format   "%c+%t"  # condition + temp. Verbose: "%c+%C+%t++💧%h++💨%w"
set -g @useful-weather-refresh  900      # seconds between wttr.in fetches
set -g @useful-weather-stale    3600     # seconds before cached data gets a "~" prefix
set -g @useful-weather-max-len  24       # cells; wttr.in error pages are not short (capped at 512)
```

A failed fetch is rate-limited to one attempt per minute rather than retried on
every refresh, so being offline costs one blocked call a minute, not one per
status tick.

### Git

```tmux
set -g @useful-git-skip-untracked "off"  # "on" speeds up dirty check in monorepos
set -g @useful-git-dirty-mark     "*"
set -g @useful-git-max-branch-len 24     # longer branches truncate with "…" (capped at 512)
```

Detached HEAD shows the short SHA as `@a1b2c3d`.

### Pane

```tmux
set -g @useful-pane-hide    "zsh bash sh fish dash tmux"   # commands to suppress (boring shells)
set -g @useful-pane-max-len 16                             # longer names truncate with "…" (capped at 512)
set -g @useful-pane-icon    ""                            # prefix glyph
```

Bare version strings (Claude Code reports its version as `pane_current_command`, e.g. `2.1.126`)
are suppressed automatically.

### Driver

```tmux
set -g @useful-render   tmux    # tmux | ansi | plain | json (default: tmux inside tmux)
set -g @useful-segments "git pane spotify system weather battery"   # order and membership
```

Both apply to `#{useful_all}` / `bin/useful-status`; the `--render` and
`--segments` flags override them.

```tmux
set -g @useful-timeout       3    # seconds any single data source may take
set -g @useful-timeout-total 10   # budget for the refresh as a whole
```

`@useful-timeout-total` **shrinks** the total, it does not cap it. Once the
budget is spent every remaining source still gets a one-second floor, so the
worst case is `@useful-timeout-total` plus about a second per guarded call still
pending. At most twelve are guarded per refresh: `system` four (two `sysctl`,
`memory_pressure`, `df`), `git` four (three git calls, plus a fourth to resolve
a detached HEAD), `spotify` two, `battery` one, `weather` one. `curl` carries
its own `--max-time` as well, but that is curl's knob: it neither honours
`@useful-timeout` nor counts against the whole-run budget, so the guard goes on
top of it rather than instead of it.

The floor is the point. Cancelling those calls outright would be tidier and was
wrong: the driver runs segments in a fixed order, so a wedged `git` blanked a
perfectly healthy `battery` further down it, and the bar went dark for a reason
that had nothing to do with the segment that vanished. A healthy source answers
in milliseconds, so the floor costs nothing when things are fine.

Set `@useful-timeout` to `0` to disable both bounds entirely.

Two bounds, because one is not enough: twelve external calls are guarded across
a refresh, so a host where everything is wedged at once — the stale-NFS case
this exists for — could block `12 x @useful-timeout` even though every
individual call honoured its limit. `@useful-timeout-total` bounds that.

`df` on a stale NFS mount, `git status` on a network filesystem and `osascript`
against a wedged Spotify can all block indefinitely. The driver runs the six
segments serially in one process, so without a bound one stuck call freezes the
whole status line — and the shell-prompt recipe above with it. A source that
outruns its budget is treated as unavailable for that refresh. Uses `timeout(1)`
where the platform has one, and a bash watchdog where it does not (macOS).

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

No icons at all? Set any icon option to `none` (or `off`). An empty string will
*not* work — tmux options treat `""` as unset, so it falls back to the default.

```tmux
set -g @useful-icon-load  "none"
set -g @useful-git-icon   "none"
```

### Text from outside the plugin

Git branch names, Spotify track titles and wttr.in responses are authored
elsewhere, so they are escaped before joining the status line: `#` becomes `##`
(tmux's literal `#`), and control characters become spaces. Without that, a
track title containing `#[bg=red]` repaints the bar, and a captive-portal
response containing a carriage return can overprint the segment's own text.

`@useful-*` option values are *not* escaped — those are your own tmux config,
already able to set any tmux option directly.

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
make check    # shellcheck + 299 bats tests
```

CI runs the matrix on macOS + Ubuntu for every push. See [AGENTS.md](AGENTS.md) for the conventions.

## Sponsor

This plugin is maintained by one person, in evenings, around a full-time job —
and it is MIT licensed for good.

If it has been quietly sitting in your status bar for months,
[sponsorship](https://github.com/sponsors/ziweiwu) is what keeps it maintained
against new tmux releases. One-time is as welcome as monthly.

**Companies:** the $100/month tier includes priority response on issues you file
and your logo here. Invoiced sponsorships available.

## License

MIT
