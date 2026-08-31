import QtQuick

// The concentric-ring glyph, fill fraction only, no numbers - shared
// between the bar icon and the popup's hero icon so both are the same
// drawing at different sizes, not two implementations that can drift
// apart. Takes a generic list of up to 3 {frac, color} entries (outer to
// inner) rather than named per-metric properties, so which metric ends
// up in which ring is driven by settings (see Panel.qml's metric
// registry), not hardcoded here.
Item {
  id: root

  property var rings: []  // [{frac, color}, ...] outer to inner, max 3
  property bool dataOk: true
  property color trackColor: "gray"

  // Reveal animation, opt-in: bind `active` to something that flips true
  // each time this instance should replay (e.g. a popup's `opened`). Left
  // false by default (revealProgress stays at 1 - fully shown, no
  // animation) so the bar-icon instance of this component is entirely
  // unaffected unless it explicitly opts in.
  //
  // This is a property binding, not a method call, because the popup's
  // content tree persists across open/close (confirmed via KeyboardPanel
  // - it fades opacity rather than destroying/recreating), so this
  // instance is created once and reused - Component.onCompleted only
  // fires the very first time, not on every re-open. A bound `active`
  // property re-fires onActiveChanged every time, matching the existing
  // heroMetaTick pattern in Panel.qml for the same reason.
  property bool active: false
  property real revealProgress: 1

  readonly property var radiusRatios: [0.46, 0.32, 0.18]

  onActiveChanged: if (active) revealAnim.restart()

  NumberAnimation {
    id: revealAnim
    target: root
    property: "revealProgress"
    from: 0; to: 1; duration: 600; easing.type: Easing.OutCubic
  }

  Canvas {
    id: canvas
    anchors.fill: parent

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var cx = width / 2, cy = height / 2
      var lineWidth = Math.max(1.2, width * 0.09)
      for (var i = 0; i < root.rings.length && i < root.radiusRatios.length; i++) {
        var ring = root.rings[i]
        var r = width * root.radiusRatios[i]
        var frac = root.dataOk ? Math.min(1, Math.max(0, ring.frac || 0)) * root.revealProgress : 0
        ctx.lineWidth = lineWidth
        ctx.strokeStyle = root.trackColor
        ctx.beginPath()
        ctx.arc(cx, cy, r, 0, Math.PI * 2)
        ctx.stroke()
        if (frac > 0) {
          ctx.strokeStyle = ring.color
          ctx.lineCap = "round"
          ctx.beginPath()
          ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + frac * Math.PI * 2)
          ctx.stroke()
        }
      }
    }

    function repaint() { requestPaint() }
  }

  onRingsChanged: canvas.repaint()
  onDataOkChanged: canvas.repaint()
  onTrackColorChanged: canvas.repaint()
  onRevealProgressChanged: canvas.repaint()
  onWidthChanged: canvas.repaint()
  onHeightChanged: canvas.repaint()
}
