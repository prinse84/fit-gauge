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

  // Sedentary nudge (issue #23). Off by default - see nudgeEnabled.
  readonly property bool nudgeEnabled: setting("sedentaryNudge", "Off") === "On"
  readonly property int nudgeSedentaryMinutes: intSetting("nudgeSedentaryMinutes", 45, 15, 180)
  readonly property int nudgeWakeHour: intSetting("nudgeWakeHour", 7, 0, 23)
  readonly property int nudgeSleepHour: intSetting("nudgeSleepHour", 23, 0, 23)
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

  // Expected steps by now, linearly paced across the configured waking
  // window - avoids nagging at 9am for being behind the full-day goal.
  function expectedSteps() {
    var now = new Date()
    var hour = now.getHours() + now.getMinutes() / 60
    var wake = root.nudgeWakeHour
    var sleepHour = root.nudgeSleepHour
    if (sleepHour <= wake) return root.stepGoal
    var frac = (hour - wake) / (sleepHour - wake)
    if (frac < 0) frac = 0
    if (frac > 1) frac = 1
    return Math.round(root.stepGoal * frac)
  }

  function behindPace() {
    if (root.steps === null || root.steps === undefined) return false
    return root.steps < root.expectedSteps()
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
  }

  function maybeNudge() {
    if (!root.nudgeEnabled || root.idleNow || root.nudgedThisStretch) return
    var minutesActive = (Date.now() - root.notIdleSinceMs) / 60000
    if (minutesActive < root.nudgeSedentaryMinutes) return
    if (!root.behindPace()) return
    root.nudgedThisStretch = true
    root.sendNudge()
  }

  function sendNudge() {
    if (nudgeProcess.running) return
    var expected = root.expectedSteps()
    var body = "You've been at the desk a while - " + (root.steps || 0) + " steps so far, pace says ~" + expected + " by now. Stand up?"
    nudgeProcess.command = ["notify-send", "-u", "normal", "-a", "Fit Gauge", "Time to move", body]
    nudgeProcess.running = true
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
    running: root.nudgeEnabled
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
