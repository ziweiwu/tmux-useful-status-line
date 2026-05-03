# Contributing

Thanks for your interest! Quick orientation:

- Engineering conventions, project anatomy, and pitfalls live in
  [`AGENTS.md`](AGENTS.md). It's named for LLM coding agents but reads just
  as well for humans — start there before opening a PR.
- Run `make check` (lint + 88 bats tests) before pushing. CI runs the same
  on every push and PR.
- macOS only at the moment. Linux support is welcome but currently the
  macOS-specific segments (`battery`, `spotify`, `system`) bail out cleanly
  on non-Darwin via `is_darwin` in `helpers.sh` — extending them is a real
  contribution opportunity.
- Defaults must stay calm. The plugin's design contract is "silent when
  healthy"; PRs that pile decoration onto routine state will be sent back.
- For new segments, follow the checklist in `AGENTS.md` ("Adding a new
  metric") — at minimum: cache aggressively, expose `@useful-<seg>-enabled`,
  and add bats tests covering healthy / warn / crit / disabled.

Bug reports with a minimal repro and the output of `tmux -V` + `uname -a`
are very helpful.
