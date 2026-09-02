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
  // updates live on a theme switch (Color.accent is a live binding).
  //
  // Colors are tied to ring SLOT (outer/mid/inner), not to a specific
  // metric - since which metric occupies which slot is now user-chosen
  // (see metricRegistry below), a metric's color changes if you move it
  // to a different ring, which is fine: rings are already disambiguated
  // by position, so color only ever needed to fit the theme, not carry
  // metric identity. Color.urgent was rejected as a ring color for the
  // same reason it was rejected before: semantically red-alert elsewhere
  // in the shell (battery-low, DND), and would clash.
  function hueRotate(base, degrees) {
    var h = base.hsvHue + degrees / 360.0
    h = h - Math.floor(h)
    return Qt.hsva(h, base.hsvSaturation, base.hsvValue, base.a)
  }
  readonly property var ringColors: [Color.accent, hueRotate(Color.accent, 35), hueRotate(Color.accent, -35)]
  readonly property color trackColor: Color.muted

  // Passive staleness cue: desaturate every ring/fill-bar color when the
  // most recent poll failed (service.healthy is false), while still
  // showing the last-known values underneath - a transient blip shouldn't
  // blank the display, just mark it as possibly out of date. Scoped to
  // poll health only (not underlying Fitbit device sync lag, which isn't
  // detectable from the data this plugin currently fetches).
  function desaturate(c) {
    return Qt.hsva(c.hsvHue, c.hsvSaturation * 0.3, c.hsvValue * 0.8, c.a)
  }
  readonly property var effectiveRingColors: service.healthy ? ringColors : ringColors.map(desaturate)

  // Sedentary-nudge ring (issue #25) - a 4th, outermost ring on the popup's
  // hero icon only (never the bar icon). Colors are theme-derived via the
  // same hueRotate() used for the 3 metric rings, at rotations well outside
  // the +-35 degrees they already use, so it reads as a different category
  // of information rather than a 4th metric. Not gated on service.healthy -
  // this is about the idle service, not Fitbit data freshness.
  readonly property color sedentaryClimbingColor: hueRotate(Color.accent, 150)
  readonly property color sedentaryOverdueColor: hueRotate(Color.accent, -150)
  readonly property bool sedentaryActive: service.nudgeEnabled && !service.idleNow
  // heroMetaTick (declared below) re-fires this every 15s while the popup
  // is open, the same trick root.heroMeta already uses to keep advancing
  // without a fresh Fitbit fetch - notIdleSinceMs itself only changes on
  // an idle/active transition, not every second.
  readonly property real sedentaryFraction: {
    heroMetaTick.tick
    return service.sedentaryFraction()
  }
  readonly property int sedentaryMinutes: {
    heroMetaTick.tick
    return Math.round(service.sedentaryElapsedMinutes())
  }
  readonly property color sedentaryRingColor: sedentaryFraction >= 1 ? sedentaryOverdueColor : sedentaryClimbingColor

  // Grows the hero icon (and, via radiusRatios, all 4 ring radii together)
  // by a fixed factor only while the 4th ring is actually shown - the 3
  // existing rings stay pixel-identical to today otherwise. See TriRingGauge
  // for why radiusRatios must change in lockstep with the size increase.
  readonly property real heroIconGrowth: 1.3
  readonly property real heroIconSize: sedentaryActive ? Style.font.display * heroIconGrowth : Style.font.display
  readonly property var heroRadiusRatios: sedentaryActive
    ? [0.46, 0.46 / heroIconGrowth, 0.32 / heroIconGrowth, 0.18 / heroIconGrowth]
    : [0.46, 0.32, 0.18]
  readonly property var heroRings: sedentaryActive
    ? [{ frac: sedentaryFraction, color: sedentaryRingColor }].concat(barRings)
    : barRings

  // Pace-nudge pill (issue #25) - independent of the sedentary ring above.
  // behindByMargin() depends on wall-clock time (the pace curve's expected
  // value drifts continuously through the day even with steps unchanged),
  // which isn't a QML property - so without reading heroMetaTick.tick here
  // too (the same trick sedentaryFraction/sedentaryMinutes/heroMeta already
  // use), this binding would only re-evaluate when steps/settings change,
  // and could sit stale-false long after time alone made it true (the
  // 30s idle-poll's maybePaceNudge() call is a separate, untied evaluation
  // that already fires the notification correctly - only this UI binding
  // was missing the tick).
  readonly property bool paceBadgeActive: {
    heroMetaTick.tick
    return service.paceNudgeEnabled && service.behindByMargin()
  }

  // Extra popup width reserved only when the bigger icon and/or the pill
  // actually need it - live-verified via screenshot that without this,
  // "SYNCED JUST NOW" truncates to "SYNCED JUST ..." when both are active
  // at once (the label column loses room to both the icon growth and the
  // pill's own reserved trailing space simultaneously).
  readonly property int contentWidthBoost: (sedentaryActive ? 30 : 0) + (paceBadgeActive ? 40 : 0)

  // Denominators the Google Health API doesn't provide (no goals endpoint
  // exists) - see manifest.json's schema for where these come from and the
  // fit-gauge project notes for how the defaults were picked (Fitbit's own
  // defaults for steps/floors, the WHO/AHA weekly-minutes guideline for
  // AZM, a fitness-press midpoint for distance - steps/AZM/distance/floors
  // each bumped 10% above baseline). calorieGoal is USDA's gender-neutral
  // moderately-active-tier EER midpoint (2300) - NOT bumped 10%, and
  // deliberately NOT an active-only figure: total-calories is total daily
  // burn (BMR + activity), confirmed live (a user saw 1091 kcal by midday
  // with only 3 AZM logged, impossible for an active-only reading that
  // low). distanceGoalMeters is stored in meters (the settings schema has
  // no non-integer type) but shown as miles.
  function goalSetting(key, fallback) {
    var value = root.settings ? root.settings[key] : undefined
    var n = parseInt(String(value === undefined || value === null ? fallback : value), 10)
    return isFinite(n) && n > 0 ? n : fallback
  }
  function stringSetting(key, fallback) {
    var value = root.settings ? root.settings[key] : undefined
    return (value === undefined || value === null || value === "") ? fallback : String(value)
  }
  readonly property int stepGoal: goalSetting("stepGoal", 11000)
  readonly property int azmGoal: goalSetting("azmGoal", 24)
  readonly property int calorieGoal: goalSetting("calorieGoal", 2300)
  readonly property int distanceGoalMeters: goalSetting("distanceGoalMeters", 8851)
  readonly property int floorsGoal: goalSetting("floorsGoal", 11)

  function fraction(value, goal) {
    if (value === null || value === undefined) return 0
    return Math.max(0, Math.min(1, value / goal))
  }

  // Row values show the current reading only, right-aligned - the fill bar
  // beneath already encodes progress toward the goal, so printing "/ 11000"
  // too would just be the same information twice. The goal itself is only
  // discoverable via plugin settings now, not from the popup - an accepted
  // tradeoff for keeping this a glance rather than a report.
  function countText(value) {
    if (value === null || value === undefined) return "—"
    return String(Math.round(value)).replace(/\B(?=(\d{3})+(?!\d))/g, ",")
  }
  function distanceText(meters) {
    if (meters === null || meters === undefined) return "—"
    return (meters / 1609.344).toFixed(1) + " mi"
  }

  // The pool every ring-selection setting picks from. Labels double as the
  // lookup key (and match manifest.json's enum options verbatim) so there's
  // one source of truth for a metric's identity instead of a separate
  // id/label pair.
  readonly property var metricRegistry: [
    { label: "Steps", value: service.steps, valueText: countText(service.steps), goal: stepGoal },
    { label: "Active Zone Minutes", value: service.activeZoneMinutes, valueText: countText(service.activeZoneMinutes), goal: azmGoal },
    { label: "Calories Burned", value: service.calories, valueText: countText(service.calories), goal: calorieGoal },
    { label: "Distance", value: service.distanceMeters, valueText: distanceText(service.distanceMeters), goal: distanceGoalMeters },
    { label: "Floors", value: service.floors, valueText: countText(service.floors), goal: floorsGoal }
  ]
  function metricByLabel(label) {
    for (var i = 0; i < metricRegistry.length; i++) {
      if (metricRegistry[i].label === label) return metricRegistry[i]
    }
    return metricRegistry[0]
  }
  // The 3 settings-selected metrics, outer to inner / row 1 to row 3.
  readonly property var selectedMetrics: [
    metricByLabel(stringSetting("ring1Metric", "Steps")),
    metricByLabel(stringSetting("ring2Metric", "Active Zone Minutes")),
    metricByLabel(stringSetting("ring3Metric", "Calories Burned"))
  ]
  readonly property var barRings: [
    { frac: fraction(selectedMetrics[0].value, selectedMetrics[0].goal), color: effectiveRingColors[0] },
    { frac: fraction(selectedMetrics[1].value, selectedMetrics[1].goal), color: effectiveRingColors[1] },
    { frac: fraction(selectedMetrics[2].value, selectedMetrics[2].goal), color: effectiveRingColors[2] }
  ]

  function sleepText(sleep) {
    if (!sleep || sleep.minutesAsleep === null || sleep.minutesAsleep === undefined) return "—"
    var h = Math.floor(sleep.minutesAsleep / 60)
    var m = sleep.minutesAsleep % 60
    return h > 0 ? (h + "h " + m + "m") : (m + "m")
  }

  // "Overnight Signals" (issue #26) - replaces the old raw Resting HR /
  // Sleep rows with one baseline-compared verdict line plus a small
  // detail caption. Verdict color reuses the same amber already
  // established for the pace-nudge "behind" state (one consistent
  // "attention" meaning across the popup) - "good"/"typical" don't get a
  // special color of their own, matching the project's habit of only
  // spending color on what's actionable.
  function overnightVerdictText() {
    if (service.overnightVerdict === "above") return "Above your usual"
    if (service.overnightVerdict === "below") return "Below your usual"
    if (service.overnightVerdict === "typical") return "Your normal"
    return "—"
  }
  function overnightVerdictColor() {
    if (service.overnightVerdict === "above") return root.foreground
    if (service.overnightVerdict === "below") return root.sedentaryOverdueColor
    return root.dim
  }
  function overnightDetailText() {
    var hrText = (service.overnightRestingHr !== null && service.overnightRestingHr !== undefined)
      ? ("RHR " + service.overnightRestingHr + " bpm") : "RHR —"
    var hrvText = (service.overnightHrv !== null && service.overnightHrv !== undefined)
      ? ("HRV " + service.overnightHrv + " ms") : "HRV —"
    var sleepDurationText = "Sleep " + root.sleepText({ minutesAsleep: service.overnightSleepMinutes })
    return [hrText, hrvText, sleepDurationText].join(" · ")
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

  // Own IpcHandler at the same target as the base Panel type's internal one
  // (same pattern as the first-party Dropbox plugin) - re-declares
  // open/close/show/hide/toggle to fully replace it, and adds refresh().
  // CLI-only, deliberately (issue #15): forcing our own poll sooner doesn't
  // fix Fitbit's device-to-cloud sync lag, so a popup refresh button isn't
  // worth the UI surface - but a scriptable/manual escape hatch for
  // confirming a fix worked (or just not waiting up to refreshIntervalSec)
  // is worth having.
  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string {
      service.refresh()
      return "ok"
    }
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
        rings: root.barRings
        dataOk: service.hasData
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
    contentWidth: panel.fittedContentWidth(Style.space(280) + root.contentWidthBoost)
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(420))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onCloseRequested: root.close()

      Column {
        id: column
        width: parent.width
        spacing: Style.space(14)

        // Hero block: title/sync line (PanelHero) plus up to 2 conditional
        // status lines (sedentary, error), tightly spaced so they read as
        // one cohesive block instead of separate floating messages. This
        // whole block keeps the outer Column's normal 14px gap before the
        // separator below - only the spacing WITHIN it is tightened.
        Column {
          id: heroBlock
          width: parent.width
          spacing: Style.space(3)

          PanelHero {
            width: parent.width
            title: "Fit Gauge"
            meta: root.heroMeta
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconComponent: Component {
              TriRingGauge {
                rings: root.heroRings
                radiusRatios: root.heroRadiusRatios
                dataOk: service.hasData
                trackColor: root.trackColor
                active: root.opened
                width: root.heroIconSize
                height: root.heroIconSize
              }
            }
            trailingControl: Component {
              PacePill {
                visible: root.paceBadgeActive
                fontFamily: root.fontFamily
              }
            }
          }

          // "At desk N min" (issue #28) - indented to align under the
          // title/meta column (icon width + PanelHero's own leftMargin),
          // matching where PanelHero's own text starts. Moved to the
          // popup's "quiet" tier (plain sentence-case, not bold, no
          // letterSpacing/uppercase) - same treatment as the Overnight
          // Signals detail caption and the #14 error line - since the 4th
          // ring already carries this state ambiently and the old loud
          // (bold/uppercase/letterSpaced) styling competed with SYNCED for
          // attention. Color still mirrors the 4th ring exactly, so the
          // color-to-meaning mapping is unchanged - only the type weight
          // softened.
          Text {
            textFormat: Text.PlainText
            visible: root.sedentaryActive
            anchors.left: parent.left
            anchors.leftMargin: root.heroIconSize + Style.space(14)
            width: parent.width - anchors.leftMargin
            text: "At desk " + root.sedentaryMinutes + " min"
            color: root.sedentaryRingColor
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            elide: Text.ElideRight
          }

          // Existing friendly-error line (#14) - deliberately NOT indented
          // and NOT styled like the caption/bold/uppercase lines above, so
          // up to 3 stacked lines don't visually blur together.
          Text {
            textFormat: Text.PlainText
            visible: !service.healthy
            width: parent.width
            text: service.lastError !== "" ? service.lastError : "Last sync failed"
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            wrapMode: Text.WordWrap
          }
        }

        PanelSeparator { foreground: root.foreground }

        Column {
          width: parent.width
          spacing: Style.space(8)

          // "TODAY" section label (issue #27) - mirrors "OVERNIGHT SIGNALS"
          // below (caption, uppercase, letterSpacing, not bold) so the
          // popup reads as two parallel labeled sections instead of one
          // labeled and one not.
          Text {
            textFormat: Text.PlainText
            text: "TODAY"
            color: root.foreground
            font.family: root.fontFamily
            font.pixelSize: Style.font.caption
            font.letterSpacing: 1.2
          }

          Column {
            width: parent.width
            spacing: Style.space(14)

            Repeater {
              model: root.selectedMetrics
              MetricRow {
                required property var modelData
                required property int index
                width: parent.width
                label: modelData.label
                value: modelData.valueText
                frac: root.fraction(modelData.value, modelData.goal)
                fillColor: root.effectiveRingColors[index]
              }
            }
          }
        }

        PanelSeparator { foreground: root.foreground }

        OvernightRow {
          width: parent.width
        }
      }
    }
  }

  // "Overnight Signals" (issue #26) - label top-left / verdict top-right,
  // echoing MetricRow's header treatment, plus a left-aligned detail
  // caption underneath (the mockup had it right-aligned; user's final
  // tweak moved it left). No FillBar here - this row is a comparison
  // verdict, not a goal-progress metric.
  component OvernightRow: Column {
    id: overnightRoot
    width: parent.width
    spacing: Style.space(8)

    Row {
      id: overnightHeaderRow
      width: parent.width

      Text {
        textFormat: Text.PlainText
        text: "OVERNIGHT SIGNALS"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.2
        width: overnightHeaderRow.width - overnightVerdictText.implicitWidth - Style.space(8)
        elide: Text.ElideRight
      }

      Item { width: Style.space(8); height: 1 }

      Text {
        id: overnightVerdictText
        textFormat: Text.PlainText
        text: root.overnightVerdictText().toUpperCase()
        color: root.overnightVerdictColor()
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.2
      }
    }

    Text {
      textFormat: Text.PlainText
      text: root.overnightDetailText()
      color: root.dim
      font.family: root.fontFamily
      font.pixelSize: Style.font.caption
      width: parent.width
      elide: Text.ElideRight
    }
  }

  // Label top-left, value top-right, a full-width fill bar underneath.
  // Fixed-width bars (not label width) are what keep the 3 rows visually
  // aligned regardless of how long each metric's label is.
  component MetricRow: Column {
    id: metricRoot
    property string label: ""
    property string value: ""
    property real frac: 0
    property color fillColor: root.foreground

    width: parent.width
    spacing: Style.space(3)

    Row {
      id: headerRow
      width: parent.width

      // Uppercase + letter-spacing (no bold - too heavy next to the thin
      // fill bars) echoes PanelHero's own sync-time treatment elsewhere
      // in this popup (root.heroMeta) to distinguish the label from the
      // value instead of a size difference, since both now share the
      // same Style.font.caption token (the smallest one available).
      Text {
        textFormat: Text.PlainText
        text: metricRoot.label.toUpperCase()
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
        font.letterSpacing: 1.2
        width: headerRow.width - valueText.implicitWidth - Style.space(8)
        elide: Text.ElideRight
      }

      Item { width: Style.space(8); height: 1 }

      Text {
        id: valueText
        textFormat: Text.PlainText
        text: metricRoot.value
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }

    FillBar {
      width: parent.width
      implicitHeight: Style.space(4)
      frac: metricRoot.frac
      fillColor: metricRoot.fillColor
      trackColor: root.trackColor
    }
  }

  // Pace-nudge pill (issue #25), used via PanelHero's trailingControl slot.
  // Reuses sedentaryOverdueColor as one shared "attention" tone across both
  // new UI elements instead of inventing a second, similar-but-different
  // amber.
  component PacePill: Item {
    id: pill
    property string fontFamily: Style.font.family
    readonly property color tint: root.sedentaryOverdueColor

    implicitWidth: row.implicitWidth + Style.space(16)
    implicitHeight: row.implicitHeight + Style.space(6)

    Rectangle {
      anchors.fill: parent
      radius: height / 2
      color: Qt.rgba(pill.tint.r, pill.tint.g, pill.tint.b, 0.14)
      border.color: Qt.rgba(pill.tint.r, pill.tint.g, pill.tint.b, 0.5)
      border.width: 1
    }

    Row {
      id: row
      anchors.centerIn: parent
      spacing: Style.space(5)

      Canvas {
        id: trendIcon
        width: Style.font.caption
        height: Style.font.caption
        anchors.verticalCenter: parent.verticalCenter
        onPaint: {
          var ctx = getContext("2d")
          ctx.reset()
          ctx.strokeStyle = pill.tint
          ctx.lineWidth = Math.max(1, width * 0.14)
          ctx.lineCap = "round"
          ctx.lineJoin = "round"
          ctx.beginPath()
          ctx.moveTo(width * 0.05, height * 0.55)
          ctx.lineTo(width * 0.35, height * 0.55)
          ctx.lineTo(width * 0.5, height * 0.15)
          ctx.lineTo(width * 0.68, height * 0.85)
          ctx.lineTo(width * 0.95, height * 0.55)
          ctx.stroke()
        }
        function repaint() { requestPaint() }
        onWidthChanged: repaint()
        onHeightChanged: repaint()
      }

      Text {
        textFormat: Text.PlainText
        text: "Behind"
        anchors.verticalCenter: parent.verticalCenter
        color: pill.tint
        font.family: pill.fontFamily
        font.pixelSize: Style.font.caption
        font.bold: true
        font.letterSpacing: 1.2
      }
    }
  }
}
