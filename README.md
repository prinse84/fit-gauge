# Fit Gauge

An Omarchy bar plugin that shows your Fitbit stats at a glance — steps, Active Zone Minutes, and calories as a small gauge in the bar, with a quick popup for the rest.

## Why

The job this does: zero-context-switch fitness awareness while you're stuck at the dev machine.

What this explicitly is **not**: a Fitbit app replacement, a historical dashboard, or a source of notifications (that's planned for later, and even then, opt-in and minimal).

## Status

Early development / pre-alpha. Not yet installable.

## Roadmap

- [ ] **v0.1 — Glance**
  - [ ] Bar gauge showing 3 hero metrics (steps / Active Zone Minutes / calories vs. goal)
  - [ ] Popup with per-metric breakdown, resting heart rate, sleep score, last-synced time
  - [ ] Passive states: desaturate on stale data, highlight on goal completion
- [ ] **v1.0 — Desk-context nudges**
  - [ ] Sedentary nudge using Omarchy's idle detection
  - [ ] Opt-in sync-lag and goal-completion notifications
- [ ] **v2.0+ — Nerd-tier (opt-in / drill-down only, never default-visible)**
  - [ ] Trend sparklines, streaks, sleep-stage breakdown, theme-colored gauges

## Requirements

- [Omarchy](https://github.com/basecamp/omarchy) (Quickshell-based bar)
- A Fitbit account and your own personal Fitbit developer app for OAuth (setup instructions coming)

## Disclaimer

Fit Gauge is an independent, community project. It is not affiliated with, endorsed by, or sponsored by Fitbit or Google. Fitbit data is accessed only through the official Fitbit Web API, under your own developer credentials.

## License

MIT — see [LICENSE](LICENSE).
