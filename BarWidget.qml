import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "prinse84.fit-gauge"

  implicitWidth: vertical ? barSize : ring.implicitSize + 12
  implicitHeight: vertical ? ring.implicitSize + 12 : barSize

  // Denominators the Google Health API doesn't provide (no goals endpoint
  // exists) - see manifest.json's schema for where these come from and the
  // fit-gauge project notes for how the defaults were picked (Fitbit's own
  // default step goal, the WHO/AHA weekly-minutes guideline for AZM, and a
  // fitness-press midpoint for calories - each bumped 10% above baseline).
  function goalSetting(key, fallback) {
    var value = root.settings ? root.settings[key] : undefined
    var n = parseInt(String(value === undefined || value === null ? fallback : value), 10)
    return isFinite(n) && n > 0 ? n : fallback
  }
  readonly property int stepGoal: goalSetting("stepGoal", 11000)
  readonly property int azmGoal: goalSetting("azmGoal", 24)
  readonly property int calorieGoal: goalSetting("calorieGoal", 440)

  function fraction(value, goal) {
    if (value === null || value === undefined) return 0
    return Math.max(0, Math.min(1, value / goal))
  }

  Service {
    id: service
    settings: root.settings
  }

  Item {
    id: ring
    readonly property int implicitSize: 26
    anchors.centerIn: parent
    width: implicitSize
    height: implicitSize

    Canvas {
      id: canvas
      anchors.fill: parent

      readonly property real stepsFrac: root.fraction(service.steps, root.stepGoal)
      readonly property real azmFrac: root.fraction(service.activeZoneMinutes, root.azmGoal)
      readonly property real calFrac: root.fraction(service.calories, root.calorieGoal)
      readonly property bool dataOk: service.ok

      onStepsFracChanged: requestPaint()
      onAzmFracChanged: requestPaint()
      onCalFracChanged: requestPaint()
      onDataOkChanged: requestPaint()

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var cx = width / 2, cy = height / 2
        var rings = [
          { r: width * 0.46, frac: dataOk ? stepsFrac : 0, color: "#5ec9f0" },
          { r: width * 0.32, frac: dataOk ? azmFrac : 0, color: "#8fe36a" },
          { r: width * 0.18, frac: dataOk ? calFrac : 0, color: "#f0a85e" }
        ]
        var lineWidth = Math.max(1.2, width * 0.09)
        for (var i = 0; i < rings.length; i++) {
          var seg = rings[i]
          ctx.lineWidth = lineWidth
          ctx.strokeStyle = "#2a2f3a"
          ctx.beginPath()
          ctx.arc(cx, cy, seg.r, 0, Math.PI * 2)
          ctx.stroke()
          if (seg.frac > 0) {
            ctx.strokeStyle = seg.color
            ctx.lineCap = "round"
            ctx.beginPath()
            ctx.arc(cx, cy, seg.r, -Math.PI / 2, -Math.PI / 2 + seg.frac * Math.PI * 2)
            ctx.stroke()
          }
        }
      }
    }
  }
}
