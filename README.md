# Fit Gauge

An Omarchy bar plugin that shows your Fitbit stats at a glance — steps, Active Zone Minutes, and calories as a small gauge in the bar, with a quick popup for the rest.

## Why

The job this does: zero-context-switch fitness awareness while you're stuck at the dev machine.

What this explicitly is **not**: a Fitbit app replacement, a historical dashboard, or a source of naggy notifications — the two nudges below are opt-in and minimal, off by default.

## Status

v0.1 (glance-only bar gauge + popup) is complete. v0.2 (desk-context nudges) is in progress — see the [issue tracker](https://github.com/prinse84/fit-gauge/issues) for what's left.

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
| `calorieGoal` | Daily calorie goal (total burn - BMR + activity, not active-only) | `2300` |
| `distanceGoalMeters` | Daily distance goal, in meters (shown as miles) | `8851` (5.5 mi) |
| `floorsGoal` | Daily floors-climbed goal | `11` |
| `refreshIntervalSec` | How often data is refetched | `300` |
| `sedentaryNudge` | Opt-in. `On` sends a desktop notification when you've been continuously active at the desk (not idle) for a while — independent of step count. Respects Do Not Disturb. | `Off` |
| `nudgeSedentaryMinutes` | How long a continuous active stretch before the stand-up nudge can fire | `45` |
| `paceNudge` | Opt-in. `On` sends at most one notification per day if you're meaningfully behind a research-informed step pace for the time of day. Independent of `sedentaryNudge`. Respects Do Not Disturb. | `Off` |
| `paceNudgeMarginPercent` | How far below expected pace (as a percent of the expected value) before the behind-pace nudge fires | `20` |

`ring1Metric`/`ring2Metric`/`ring3Metric` each accept one of: `Steps`, `Active Zone Minutes`, `Calories Burned`, `Distance`, `Floors`. Multi-word values need quoting:

```
omarchy bar set prinse84.fit-gauge ring1Metric "Active Zone Minutes"
```

Distance and Floors aren't a v0.1 focus — they're available if you want them, but weren't part of the default design, and Floors in particular depends on your Fitbit device reporting that data at all (not every device has a barometric altimeter).

### Nudges

Both nudges are desktop notifications (`notify-send`), off by default, and automatically silenced by Do Not Disturb — Omarchy's own shell is the notification server, so DND is handled for free, no extra setting needed here.

- **Stand-up nudge** (`sedentaryNudge`) fires once per continuous desk stretch once you cross `nudgeSedentaryMinutes`, and re-arms only after you actually take a break (not on a timer).
- **Behind-pace nudge** (`paceNudge`) fires at most once a day if your steps are behind a pace curve modeled on published step-accumulation research (three daily peaks — commute/lunch/evening — with dips at typical desk hours), by more than `paceNudgeMarginPercent`.

## Roadmap

- [x] **v0.1 — Glance**
  - [x] Bar gauge showing 3 hero metrics (steps / Active Zone Minutes / calories vs. goal)
  - [x] Popup with per-metric breakdown, resting heart rate, sleep duration, last-synced time
  - [x] Passive states: desaturate on stale data
- [x] **v0.2 — Desk-context nudges**
  - [x] Stand-up nudge: prompt to move after a long continuous sedentary stretch (opt-in)
  - [x] Behind-pace nudge: once-a-day prompt if steps are meaningfully behind a research-informed pace for the time of day (opt-in)
- [ ] **v1.0 — More opt-in notifications**
  - [ ] Sync-lag and goal-completion notifications
- [ ] **v2.0+ — Nerd-tier (opt-in / drill-down only, never default-visible)**
  - [ ] Trend sparklines, streaks, sleep-stage breakdown, theme-colored gauges

## Requirements

- [Omarchy](https://github.com/basecamp/omarchy) (Quickshell-based bar)
- A Fitbit account synced to Google Health, and your own Google Cloud OAuth client for the Google Health API (setup instructions coming)

## Disclaimer

Fit Gauge is an independent, community project. It is not affiliated with, endorsed by, or sponsored by Fitbit or Google. Fitbit data is accessed only through the official Google Health API, under your own Google Cloud OAuth credentials.

## License

MIT — see [LICENSE](LICENSE).
