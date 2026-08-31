import QtQuick
import Quickshell.Io
import qs.Commons
import qs.Ui

// Bar icon + click popup in one entry point, matching the platform's own
// pattern for icon-and-popup bar widgets (Dropbox, battery, bluetooth,
// etc. all extend Panel this way rather than BarWidget). Read-only glance:
// no login/action flow, no scrollable list, so no cursor navigation - just
// Escape/outside-click to dismiss.
Panel {
  id: root
  moduleName: "prinse84.fit-gauge"
  ipcTarget: "prinse84.fit-gauge"

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color dim: Qt.darker(foreground, 1.4)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  // Hue-rotates a QML color in HSV space, wrapping back into [0,1). Derives
  // the 3 ring colors from the theme's own accent instead of fixed hex
  // values, so the glyph matches whatever Omarchy theme is active and
  // updates live on a theme switch (Color.accent is a live binding). Rings
  // are already disambiguated by position (outer/mid/inner, or row order
  // in the popup), so color only needs to fit the theme, not carry metric
  // identity - Color.urgent was rejected as a ring color for this reason:
  // it's semantically red-alert elsewhere in the shell (battery-low, DND)
  // and would clash.
  function hueRotate(base, degrees) {
    var h = base.hsvHue + degrees / 360.0
    h = h - Math.floor(h)
    return Qt.hsva(h, base.hsvSaturation, base.hsvValue, base.a)
  }
  readonly property color stepColor: Color.accent
  readonly property color azmColor: hueRotate(Color.accent, 35)
  readonly property color calorieColor: hueRotate(Color.accent, -35)
  readonly property color trackColor: Color.muted

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

  function countText(value, goal) {
    return value !== null && value !== undefined ? value + " / " + goal : "—"
  }

  function sleepText(sleep) {
    if (!sleep || sleep.minutesAsleep === null || sleep.minutesAsleep === undefined) return "—"
    var h = Math.floor(sleep.minutesAsleep / 60)
    var m = sleep.minutesAsleep % 60
    return h > 0 ? (h + "h " + m + "m") : (m + "m")
  }

  function lastSyncedText() {
    if (!service.fetchedAtIso) return "Not synced yet"
    var synced = new Date(service.fetchedAtIso)
    if (isNaN(synced.getTime())) return "Not synced yet"
    var minutes = Math.floor((Date.now() - synced.getTime()) / 60000)
    if (minutes < 1) return "Synced just now"
    if (minutes === 1) return "Synced 1 min ago"
    if (minutes < 60) return "Synced " + minutes + " min ago"
    var hours = Math.floor(minutes / 60)
    return "Synced " + hours + (hours === 1 ? " hour ago" : " hours ago")
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  Service {
    id: service
    settings: root.settings
  }

  // Keeps the "Synced N min ago" meta line advancing while the popup is
  // open, without needing a fresh fetch. lastSyncedText() reads Date.now(),
  // which isn't itself a QML property the binding can depend on, so
  // heroMeta reads this ticking property purely to pick up a dependency.
  Timer {
    interval: 15000
    running: root.opened
    repeat: true
    onTriggered: heroMetaTick.tick = !heroMetaTick.tick
  }
  QtObject {
    id: heroMetaTick
    property bool tick: false
  }
  readonly property string heroMeta: {
    heroMetaTick.tick
    return root.lastSyncedText()
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    iconComponent: Component {
      TriRingGauge {
        stepsFrac: root.fraction(service.steps, root.stepGoal)
        azmFrac: root.fraction(service.activeZoneMinutes, root.azmGoal)
        calFrac: root.fraction(service.calories, root.calorieGoal)
        dataOk: service.ok
        stepColor: root.stepColor
        azmColor: root.azmColor
        calorieColor: root.calorieColor
        trackColor: root.trackColor
      }
    }
    onPressed: function(buttonCode) { root.toggle() }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(260))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(420))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: column
        width: parent.width
        spacing: Style.space(14)

        PanelHero {
          width: parent.width
          title: "Fit Gauge"
          meta: root.heroMeta
          foreground: root.foreground
          fontFamily: root.fontFamily
          iconComponent: Component {
            TriRingGauge {
              stepsFrac: root.fraction(service.steps, root.stepGoal)
              azmFrac: root.fraction(service.activeZoneMinutes, root.azmGoal)
              calFrac: root.fraction(service.calories, root.calorieGoal)
              dataOk: service.ok
              stepColor: root.stepColor
              azmColor: root.azmColor
              calorieColor: root.calorieColor
              trackColor: root.trackColor
              width: Style.font.display
              height: Style.font.display
            }
          }
        }

        Column {
          width: parent.width
          spacing: Style.space(10)

          MetricRow {
            label: "Steps"
            value: root.countText(service.steps, root.stepGoal)
            frac: root.fraction(service.steps, root.stepGoal)
            ringColor: root.stepColor
          }
          MetricRow {
            label: "Active Zone Minutes"
            value: root.countText(service.activeZoneMinutes, root.azmGoal)
            frac: root.fraction(service.activeZoneMinutes, root.azmGoal)
            ringColor: root.azmColor
          }
          MetricRow {
            label: "Calories"
            value: root.countText(service.calories, root.calorieGoal)
            frac: root.fraction(service.calories, root.calorieGoal)
            ringColor: root.calorieColor
          }
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.spacing.labelGap

          InfoPair {
            label: "Resting HR"
            value: service.restingHeartRate !== null ? service.restingHeartRate + " bpm" : "—"
          }
          InfoPair {
            label: "Sleep"
            value: root.sleepText(service.sleep)
          }
        }
      }
    }
  }

  component MetricRow: Row {
    property string label: ""
    property string value: ""
    property real frac: 0
    property color ringColor: root.foreground

    width: parent.width
    spacing: Style.space(10)

    RingGauge {
      width: Style.font.title
      height: Style.font.title
      anchors.verticalCenter: parent.verticalCenter
      frac: parent.frac
      ringColor: parent.ringColor
      trackColor: root.trackColor
    }

    Text {
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: parent.label
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.body
      width: Math.max(0, parent.width - parent.children[0].width - valueText.implicitWidth - parent.spacing * 2)
      elide: Text.ElideRight
    }

    Text {
      id: valueText
      textFormat: Text.PlainText
      anchors.verticalCenter: parent.verticalCenter
      text: parent.value
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
  }

  component InfoPair: Row {
    property string label: ""
    property string value: ""

    width: parent.width
    spacing: Style.space(8)

    Text {
      textFormat: Text.PlainText
      text: parent.label
      color: root.foreground
      opacity: 0.6
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
    }
    Item {
      width: Math.max(0, parent.width - parent.children[0].implicitWidth - parent.children[2].implicitWidth - parent.spacing * 2)
      height: 1
    }
    Text {
      textFormat: Text.PlainText
      text: parent.value
      color: root.foreground
      font.family: root.fontFamily
      font.pixelSize: Style.font.bodySmall
      elide: Text.ElideRight
    }
  }
}
