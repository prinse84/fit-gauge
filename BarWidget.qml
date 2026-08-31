import QtQuick
import qs.Ui
import qs.Commons

BarWidget {
  id: root
  moduleName: "prinse84.fit-gauge"

  implicitWidth: vertical ? barSize : ring.implicitSize + ring.padding * 2
  implicitHeight: vertical ? ring.implicitSize + ring.padding * 2 : barSize

  // Hue-rotates a QML color in HSV space, wrapping back into [0,1). Derives
  // the 3 ring colors from the theme's own accent instead of fixed hex
  // values, so the glyph matches whatever Omarchy theme is active and
  // updates live on a theme switch (Color.accent is a live binding). Rings
  // are already disambiguated by position (outer/mid/inner), so color only
  // needs to fit the theme, not carry metric identity - Color.urgent was
  // rejected as a ring color for this reason: it's semantically red-alert
  // elsewhere in the shell (battery-low, DND) and would clash.
  function hueRotate(base, degrees) {
    var h = base.hsvHue + degrees / 360.0
    h = h - Math.floor(h)
    return Qt.hsva(h, base.hsvSaturation, base.hsvValue, base.a)
  }
  readonly property color stepColor: Color.accent
  readonly property color azmColor: hueRotate(Color.accent, 35)
  readonly property color calorieColor: hueRotate(Color.accent, -35)

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
    // Matches WidgetButton's own default padding convention (qs.Ui) so the
    // glyph reads at the same visual scale as sibling icons instead of
    // filling the slot edge-to-edge, and stays proportional if the user
    // changes the bar size or spacing density (Style.space scales with
    // both) via `omarchy bar` settings.
    readonly property real padding: Style.space(6)
    readonly property real implicitSize: Math.max(8, root.barSize - padding * 2)
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
      readonly property color trackColor: Color.muted
      readonly property color stepColor: root.stepColor
      readonly property color azmColor: root.azmColor
      readonly property color calorieColor: root.calorieColor

      onStepsFracChanged: requestPaint()
      onAzmFracChanged: requestPaint()
      onCalFracChanged: requestPaint()
      onDataOkChanged: requestPaint()
      onTrackColorChanged: requestPaint()
      onStepColorChanged: requestPaint()
      onAzmColorChanged: requestPaint()
      onCalorieColorChanged: requestPaint()

      onPaint: {
        var ctx = getContext("2d")
        ctx.reset()
        var cx = width / 2, cy = height / 2
        var rings = [
          { r: width * 0.46, frac: dataOk ? stepsFrac : 0, color: stepColor },
          { r: width * 0.32, frac: dataOk ? azmFrac : 0, color: azmColor },
          { r: width * 0.18, frac: dataOk ? calFrac : 0, color: calorieColor }
        ]
        var lineWidth = Math.max(1.2, width * 0.09)
        for (var i = 0; i < rings.length; i++) {
          var seg = rings[i]
          ctx.lineWidth = lineWidth
          ctx.strokeStyle = trackColor
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
