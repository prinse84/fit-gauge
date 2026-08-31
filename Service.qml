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

  property bool ok: false
  property string fetchedAtIso: ""
  property var steps: null
  property var activeZoneMinutes: null
  property var calories: null
  property var restingHeartRate: null
  property var sleep: null
  property var warnings: []
  property string lastError: ""
  property bool refreshing: false

  property string _stdout: ""
  property string _stderr: ""

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

  function applyStatus(raw) {
    var parsed
    try {
      parsed = JSON.parse(raw)
    } catch (e) {
      lastError = "Failed to parse fitbit_status.py output"
      return
    }
    if (!parsed.ok) {
      lastError = parsed.error || "fitbit_status.py reported an error"
      return
    }
    ok = true
    fetchedAtIso = parsed.fetchedAtIso || ""
    steps = parsed.steps
    activeZoneMinutes = parsed.activeZoneMinutes
    calories = parsed.calories
    restingHeartRate = parsed.restingHeartRate
    sleep = parsed.sleep
    warnings = parsed.warnings || []
    lastError = ""
  }

  Timer {
    id: refreshTimer
    interval: root.refreshIntervalSec * 1000
    repeat: true
    running: true
    triggeredOnStart: true
    onTriggered: root.refresh()
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
      else root.lastError = stderr || ("fitbit_status.py exited " + exitCode)
    }
  }
}
