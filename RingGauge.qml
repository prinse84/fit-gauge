import QtQuick

// A single fill ring - the popup's per-metric row icon. Same drawing logic
// as one ring of TriRingGauge, factored out since the popup shows each
// metric as its own small ring rather than one concentric glyph.
Item {
  id: root

  property real frac: 0
  property color ringColor: "white"
  property color trackColor: "gray"

  Canvas {
    id: canvas
    anchors.fill: parent

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var cx = width / 2, cy = height / 2
      var lineWidth = Math.max(1.2, width * 0.16)
      var r = width / 2 - lineWidth / 2
      ctx.lineWidth = lineWidth
      ctx.strokeStyle = root.trackColor
      ctx.beginPath()
      ctx.arc(cx, cy, r, 0, Math.PI * 2)
      ctx.stroke()
      if (root.frac > 0) {
        ctx.strokeStyle = root.ringColor
        ctx.lineCap = "round"
        ctx.beginPath()
        ctx.arc(cx, cy, r, -Math.PI / 2, -Math.PI / 2 + Math.min(1, root.frac) * Math.PI * 2)
        ctx.stroke()
      }
    }

    function repaint() { requestPaint() }
  }

  onFracChanged: canvas.repaint()
  onRingColorChanged: canvas.repaint()
  onTrackColorChanged: canvas.repaint()
  onWidthChanged: canvas.repaint()
  onHeightChanged: canvas.repaint()
}
