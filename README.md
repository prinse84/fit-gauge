# Fit Gauge

An Omarchy bar plugin that shows your Fitbit stats at a glance — steps, Active Zone Minutes, and calories as a small gauge in the bar, with a quick popup for the rest.

## Why

The job this does: zero-context-switch fitness awareness while you're stuck at the dev machine.

What this explicitly is **not**: a Fitbit app replacement, a historical dashboard, or a source of notifications (that's planned for later, and even then, opt-in and minimal).

## Status

Early development. Live in the bar, working end to end (steps/AZM/calories/resting HR/sleep, click popup, theming) — see the [issue tracker](https://github.com/prinse84/fit-gauge/issues) for what's left before v0.1 is complete.

## Settings

No settings GUI (a CLI is all this needs for now) — configure via `omarchy bar set`:

```
omarchy bar set prinse84.fit-gauge <key> <value>
```

| Key | What it does | Default |
|---|---|---|
| `ring1Metric` | Outer ring / first popup row | `Steps` |
| `ring2Metric` | Middle ring / second popup row | `Active Zone Minutes` |
| `ring3Metric` | Inner ring / third popup row | `Calories Burned` |
| `stepGoal` | Daily step goal | `11000` |
| `azmGoal` | Daily Active Zone Minutes goal | `24` |
| `calorieGoal` | Daily active-calorie goal | `440` |
| `distanceGoalMeters` | Daily distance goal, in meters (shown as miles) | `8851` (5.5 mi) |
| `floorsGoal` | Daily floors-climbed goal | `11` |
| `refreshIntervalSec` | How often data is refetched | `300` |

`ring1Metric`/`ring2Metric`/`ring3Metric` each accept one of: `Steps`, `Active Zone Minutes`, `Calories Burned`, `Distance`, `Floors`. Multi-word values need quoting:

```
omarchy bar set prinse84.fit-gauge ring1Metric "Active Zone Minutes"
```

Distance and Floors aren't a v0.1 focus — they're available if you want them, but weren't part of the default design, and Floors in particular depends on your Fitbit device reporting that data at all (not every device has a barometric altimeter).

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
- A Fitbit account synced to Google Health, and your own Google Cloud OAuth client for the Google Health API (setup instructions coming)

## Disclaimer

Fit Gauge is an independent, community project. It is not affiliated with, endorsed by, or sponsored by Fitbit or Google. Fitbit data is accessed only through the official Google Health API, under your own Google Cloud OAuth credentials.

## License

MIT — see [LICENSE](LICENSE).
