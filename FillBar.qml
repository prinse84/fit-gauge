import QtQuick

// Read-only progress fill - the same rounded track+fill visual language as
// qs.Ui/PanelSlider (used for volume/brightness), without the knob, drag,
// or MouseArea that would make a display-only stat look interactive.
Item {
  id: root

  property real frac: 0
  property color fillColor: "white"
  property color trackColor: "gray"

  implicitHeight: 6

  Rectangle {
    id: track
    anchors.fill: parent
    radius: height / 2
    color: root.trackColor
  }

  Rectangle {
    id: fill
    anchors.left: track.left
    anchors.top: track.top
    anchors.bottom: track.bottom
    radius: track.radius
    color: root.fillColor
    width: track.width * Math.max(0, Math.min(1, root.frac))

    Behavior on width {
      NumberAnimation { duration: 140; easing.type: Easing.OutCubic }
    }
  }
}
