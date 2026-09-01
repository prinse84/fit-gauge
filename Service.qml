import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var settings: ({})

  // Sibling script + venv. The venv path is a dev-machine convention for
  // now (see fitbit_status.py's home in ~/.cache/fit-gauge/venv) - real
  // distribution will need a proper install story, not a hardcoded path.
  readonly property string helperPath: String(Qt.resolvedUrl("fitbit_status.py")).substring(7)
  readonly property string pythonPath: Quickshell.env("HOME") + "/.cache/fit-gauge/venv/bin/python"

  readonly property int refreshIntervalSec: intSetting("refreshIntervalSec", 300, 60, 3600)
  readonly property bool busy: fetchProcess.running

  // Stand-up nudge (issue #23). Off by default - see nudgeEnabled. Pure
  // sedentary duration, no step data involved.
  readonly property bool nudgeEnabled: setting("sedentaryNudge", "Off") === "On"
  readonly property int nudgeSedentaryMinutes: intSetting("nudgeSedentaryMinutes", 45, 15, 180)

  // Pace nudge (issue #24). Off by default - see paceNudgeEnabled.
  // Independent of the stand-up nudge above; uses the pace curve below.
  readonly property bool paceNudgeEnabled: setting("paceNudge", "Off") === "On"
  readonly property int paceNudgeMarginPercent: intSetting("paceNudgeMarginPercent", 20, 5, 50)
  readonly property int stepGoal: intSetting("stepGoal", 11000, 1000, 50000)

  // hasData latches true forever once any fetch has ever succeeded - it
  // gates whether there's anything to render at all (first-load state).
  // healthy reflects only the MOST RECENT poll and resets on every
  // failure - this is what drives the stale/desaturated visual, so a
  // transient network blip doesn't blank last-known-good values, it just
  // marks them stale until the next successful poll.
  property bool hasData: false
  property bool healthy: false
  property string fetchedAtIso: ""
  property var steps: null
  property var activeZoneMinutes: null
  property var calories: null
  property var distanceMeters: null
  property var floors: null
  property var restingHeartRate: null
  property var sleep: null
  property var warnings: []
  property string lastError: ""
  property bool refreshing: false

  property string _stdout: ""
  property string _stderr: ""

  // Sedentary-nudge state. notIdleSinceMs marks the start of the current
  // continuous-active stretch; nudgedThisStretch re-arms only when idle
  // flips true again (a real break), never on a flat cooldown.
  property bool idleKnown: false
  property bool idleNow: true
  property double notIdleSinceMs: 0
  property bool nudgedThisStretch: false
  property string paceNudgedDate: ""

  function setting(name, fallback) {
    var value = settings ? settings[name] : undefined
    return value === undefined || value === null ? fallback : value
  }

  function intSetting(name, fallback, min, max) {
    var n = parseInt(String(setting(name, fallback)), 10)
    if (!isFinite(n)) n = fallback
    if (n < min) n = min
    if (n > max) n = max
    return n
  }

  function refresh() {
    if (fetchProcess.running) return
    refreshing = true
    _stdout = ""
    _stderr = ""
    fetchProcess.command = [pythonPath, helperPath]
    fetchProcess.running = true
  }

  // Only for a process that never produced any stdout at all - i.e. it
  // couldn't even start (missing script/venv), as opposed to a script
  // that ran and reported its own error via JSON (already a friendly
  // message from fitbit_status.py itself by the time it reaches
  // applyStatus's !parsed.ok branch below). This is a shell/exec-level
  // failure Python never sees, so it can only be handled here.
  function friendlyProcessError(raw) {
    if (raw.indexOf("No such file or directory") !== -1) {
      return "Fit Gauge isn't set up correctly - the fetch script or its Python environment is missing."
    }
    return raw
  }

  function applyStatus(raw) {
    var parsed
    try {
      parsed = JSON.parse(raw)
    } catch (e) {
      lastError = "Failed to parse fitbit_status.py output"
      healthy = false
      return
    }
    if (!parsed.ok) {
      lastError = parsed.error || "fitbit_status.py reported an error"
      healthy = false
      return
    }
    hasData = true
    healthy = true
    fetchedAtIso = parsed.fetchedAtIso || ""
    steps = parsed.steps
    activeZoneMinutes = parsed.activeZoneMinutes
    calories = parsed.calories
    distanceMeters = parsed.distanceMeters
    floors = parsed.floors
    restingHeartRate = parsed.restingHeartRate
    sleep = parsed.sleep
    warnings = parsed.warnings || []
    lastError = ""
  }

  // Anchors approximating published hourly step-pattern research (three
  // weekday peaks - commute/lunch/evening - with dips during typical desk
  // hours in between), grounded at one hard data point: ~70% of goal by 7pm
  // predicts hitting the daily goal by end of day (Communications Medicine
  // 2024, "Hourly step recommendations to achieve daily goals for working
  // adults"). An opinionated, evidence-informed shape, not a precise curve
  // for this app's own users - same spirit as the goal defaults.
  readonly property var paceAnchors: [
    { h: 7, f: 0.00 },
    { h: 9, f: 0.15 },
    { h: 11, f: 0.20 },
    { h: 13, f: 0.40 },
    { h: 16, f: 0.48 },
    { h: 19, f: 0.70 },
    { h: 23, f: 1.00 }
  ]

  function expectedStepsFraction() {
    var now = new Date()
    var hour = now.getHours() + now.getMinutes() / 60
    var anchors = root.paceAnchors
    if (hour <= anchors[0].h) return anchors[0].f
    for (var i = 0; i < anchors.length - 1; i++) {
      var a = anchors[i]
      var b = anchors[i + 1]
      if (hour <= b.h) {
        var t = (hour - a.h) / (b.h - a.h)
        return a.f + t * (b.f - a.f)
      }
    }
    return anchors[anchors.length - 1].f
  }

  function expectedSteps() {
    return Math.round(root.stepGoal * root.expectedStepsFraction())
  }

  // Behind by more than a margin (percent of expected), not just any gap -
  // the expected value is intentionally low during desk-hour dips, so a
  // tiny absolute miss there shouldn't count as "behind".
  function behindByMargin() {
    if (root.steps === null || root.steps === undefined) return false
    var expected = root.expectedSteps()
    var threshold = expected * (1 - root.paceNudgeMarginPercent / 100)
    return root.steps < threshold
  }

  // Popup UI (issue #25) reads these to drive the hero icon's 4th ring and
  // the "AT DESK N MIN" line - separate from the notification-firing logic
  // above, which only cares about crossing the threshold once.
  function sedentaryElapsedMinutes() {
    if (root.idleNow) return 0
    return Math.max(0, (Date.now() - root.notIdleSinceMs) / 60000)
  }

  function sedentaryFraction() {
    if (root.nudgeSedentaryMinutes <= 0) return 0
    return Math.min(1, root.sedentaryElapsedMinutes() / root.nudgeSedentaryMinutes)
  }

  function applyIdleStatus(raw) {
    var parsed
    try {
      parsed = JSON.parse(raw)
    } catch (e) {
      return
    }
    var idle = !!parsed.idle
    if (!root.idleKnown) {
      root.idleKnown = true
      if (!idle) root.notIdleSinceMs = Date.now()
    } else if (idle !== root.idleNow) {
      if (idle) root.nudgedThisStretch = false
      else root.notIdleSinceMs = Date.now()
    }
    root.idleNow = idle
    root.maybeNudge()
    root.maybePaceNudge()
  }

  // Stand-up nudge: pure sedentary duration, no steps involved at all -
  // prolonged uninterrupted sitting matters regardless of today's step
  // total. Re-arms only when idle flips true again (a real break).
  function maybeNudge() {
    if (!root.nudgeEnabled || root.idleNow || root.nudgedThisStretch) return
    var minutesActive = (Date.now() - root.notIdleSinceMs) / 60000
    if (minutesActive < root.nudgeSedentaryMinutes) return
    root.nudgedThisStretch = true
    root.sendNudge()
  }

  function sendNudge() {
    if (nudgeProcess.running) return
    var body = "You've been at the desk a while. Stand up, stretch, grab some water?"
    nudgeProcess.command = ["notify-send", "-u", "normal", "-a", "Fit Gauge", "Time to move", body]
    nudgeProcess.running = true
  }

  // Pace nudge: independent of sedentary duration - a once-a-day "today is
  // trending behind" check using the pace curve above. Re-arms at the next
  // calendar day, not on idle transitions.
  function maybePaceNudge() {
    if (!root.paceNudgeEnabled || root.idleNow) return
    var todayStr = Qt.formatDate(new Date(), "yyyy-MM-dd")
    if (root.paceNudgedDate === todayStr) return
    if (!root.behindByMargin()) return
    root.paceNudgedDate = todayStr
    root.sendPaceNudge()
  }

  function sendPaceNudge() {
    if (paceNudgeProcess.running) return
    var expected = root.expectedSteps()
    var body = "You're at " + (root.steps || 0) + " steps - typical pace for this time of day is around " + expected + ". A short walk would help close the gap."
    paceNudgeProcess.command = ["notify-send", "-u", "normal", "-a", "Fit Gauge", "Behind pace today", body]
    paceNudgeProcess.running = true
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
  }

  Timer {
    id: idlePollTimer
    interval: 30000
    repeat: true
    running: root.nudgeEnabled || root.paceNudgeEnabled
    triggeredOnStart: true
    onTriggered: if (!idleProcess.running) idleProcess.running = true
  }

  Process {
    id: idleProcess
    running: false
    command: ["omarchy-shell", "idle", "status"]
    stdout: StdioCollector { id: idleStdout; waitForEnd: true; onStreamFinished: root.applyIdleStatus(text) }
  }

  Process {
    id: nudgeProcess
    running: false
    command: []
  }

  Process {
    id: paceNudgeProcess
    running: false
    command: []
  }

  Process {
    id: fetchProcess
    running: false
    command: []
    stdout: StdioCollector { id: fetchStdout; waitForEnd: true; onStreamFinished: root._stdout = text }
    stderr: StdioCollector { id: fetchStderr; waitForEnd: true; onStreamFinished: root._stderr = text }
    onExited: function(exitCode) {
      root.refreshing = false
      var stdout = String(fetchStdout.text || root._stdout || "")
      var stderr = String(fetchStderr.text || root._stderr || "")
      if (stdout.length > 0) root.applyStatus(stdout)
      else {
        root.lastError = root.friendlyProcessError(stderr || ("fitbit_status.py exited " + exitCode))
        root.healthy = false
      }
    }
  }
}
