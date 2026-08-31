import QtQuick
import qs.Ui

BarWidget {
  id: root
  moduleName: "prinse84.fit-gauge"

  implicitWidth: vertical ? barSize : label.implicitWidth + 12
  implicitHeight: vertical ? label.implicitHeight + 12 : barSize

  // Text-only placeholder proving the data pipe works end to end. Real
  // gauge rendering (rings/bars, per-metric goals) is a separate step.
  readonly property string displayText: {
    if (!service.ok && service.lastError !== "") return "!"
    if (!service.ok) return "◎"
    return service.steps !== null ? String(service.steps) : "◎"
  }

  Service {
    id: service
    settings: root.settings
  }

  Text {
    id: label
    anchors.centerIn: parent
    text: root.displayText
    color: root.bar ? root.bar.foreground : "white"
    font.family: root.bar ? root.bar.fontFamily : "monospace"
    font.pixelSize: 14
  }
}
