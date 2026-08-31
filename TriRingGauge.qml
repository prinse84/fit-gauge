import QtQuick

// The 3-concentric-ring glyph (steps outer, AZM mid, calories inner), fill
// fraction only, no numbers - shared between the bar icon and the popup's
// hero icon so both are the same drawing at different sizes, not two
// implementations that can drift apart.
Item {
  id: root

  property real stepsFrac: 0
  property real azmFrac: 0
  property real calFrac: 0
  property bool dataOk: true
  property color stepColor: "white"
  property color azmColor: "white"
  property color calorieColor: "white"
  property color trackColor: "gray"

  Canvas {
    id: canvas
    anchors.fill: parent

    onPaint: {
      var ctx = getContext("2d")
      ctx.reset()
      var cx = width / 2, cy = height / 2
      var rings = [
        { r: width * 0.46, frac: root.dataOk ? root.stepsFrac : 0, color: root.stepColor },
        { r: width * 0.32, frac: root.dataOk ? root.azmFrac : 0, color: root.azmColor },
        { r: width * 0.18, frac: root.dataOk ? root.calFrac : 0, color: root.calorieColor }
      ]
      var lineWidth = Math.max(1.2, width * 0.09)
      for (var i = 0; i < rings.length; i++) {
        var seg = rings[i]
        ctx.lineWidth = lineWidth
        ctx.strokeStyle = root.trackColor
        ctx.beginPath()
        ctx.arc(cx, cy, seg.r, 0, Math.PI * 2)
        ctx.stroke()
        if (seg.frac > 0) {
          ctx.strokeStyle = seg.color
          ctx.lineCap = "round"
          ctx.beginPath()
          ctx.arc(cx, cy, seg.r, -Math.PI / 2, -Math.PI / 2 + Math.min(1, seg.frac) * Math.PI * 2)
          ctx.stroke()
        }
      }
    }

    function repaint() { requestPaint() }
  }

  onStepsFracChanged: canvas.repaint()
  onAzmFracChanged: canvas.repaint()
  onCalFracChanged: canvas.repaint()
  onDataOkChanged: canvas.repaint()
  onStepColorChanged: canvas.repaint()
  onAzmColorChanged: canvas.repaint()
  onCalorieColorChanged: canvas.repaint()
  onTrackColorChanged: canvas.repaint()
  onWidthChanged: canvas.repaint()
  onHeightChanged: canvas.repaint()
}
