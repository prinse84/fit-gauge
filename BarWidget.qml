import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "prinse84.fit-gauge"

  implicitWidth: vertical ? barSize : label.implicitWidth + 12
  implicitHeight: vertical ? label.implicitHeight + 12 : barSize

  Text {
    id: label
    anchors.centerIn: parent
    text: "◎"
    color: root.bar ? root.bar.foreground : "white"
    font.family: root.bar ? root.bar.fontFamily : "monospace"
    font.pixelSize: 14
  }
}
